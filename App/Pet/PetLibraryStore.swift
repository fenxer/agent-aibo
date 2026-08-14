import AiboCore
import AppKit
import Foundation

@MainActor
@Observable
final class PetLibraryStore {
    static let shared = PetLibraryStore()

    private(set) var records: [PetLibraryRecord] = [.builtInDefault]
    private(set) var selectedID: String = PetLibraryDefaults.builtInID
    private(set) var lastErrorMessage: String?
    private(set) var isInstalling = false

    private let installer = PetdexInstaller()

    var selectedRecord: PetLibraryRecord {
        records.first(where: { $0.id == selectedID }) ?? .builtInDefault
    }

    /// Allocated size of `AiboPaths.petsDirectory` (installed pets + `library.json`).
    func occupiedDiskBytes() -> Int64 {
        let root = AiboPaths.petsDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return 0 }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private init() {
        reloadFromDisk()
    }

    func reloadFromDisk() {
        let file = loadFile()
        let snap = PetLibraryCodec.snapshot(from: file)
        selectedID = snap.selectedID
        records = snap.records
    }

    func select(id: String) {
        guard records.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
        notifyAppearanceChanged()
    }

    func installPetdex(from slugOrURL: String) async {
        guard !isInstalling else { return }
        isInstalling = true
        lastErrorMessage = nil
        defer { isInstalling = false }

        do {
            let record = try await installer.install(slugOrURL: slugOrURL)
            upsert(record)
            selectedID = record.id
            persist()
            notifyAppearanceChanged()
        } catch let error as PetdexInstallError {
            lastErrorMessage = Self.message(for: error)
        } catch {
            lastErrorMessage = String(localized: "Failed to install pet")
        }
    }

    func importStaticImage(from sourceURL: URL, displayName: String? = nil) {
        lastErrorMessage = nil
        do {
            try FileManager.default.createDirectory(
                at: AiboPaths.staticPetsDirectory,
                withIntermediateDirectories: true
            )

            let ext = sourceURL.pathExtension.lowercased()
            let allowed = ["png", "jpg", "jpeg", "webp", "heic", "tif", "tiff"]
            guard allowed.contains(ext) else {
                lastErrorMessage = String(localized: "Unsupported image file")
                return
            }

            let id = UUID().uuidString.lowercased()
            let fileName = "\(id).\(ext)"
            let destination = AiboPaths.staticPetsDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = PetLibraryRecord(
                id: "static.\(id)",
                kind: .staticImage,
                displayName: (name?.isEmpty == false ? name! : sourceURL.deletingPathExtension().lastPathComponent),
                relativePath: "\(AiboPaths.staticPetsDirectoryName)/\(fileName)"
            )
            upsert(record)
            selectedID = record.id
            persist()
            notifyAppearanceChanged()
        } catch {
            lastErrorMessage = String(localized: "Failed to import image")
        }
    }

    func remove(id: String) {
        guard let record = records.first(where: { $0.id == id }), record.isRemovable else { return }
        records.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = PetLibraryDefaults.builtInID
        }

        let absolute = AiboPaths.petsDirectory.appendingPathComponent(record.relativePath)
        try? FileManager.default.removeItem(at: absolute)

        persist()
        notifyAppearanceChanged()
    }

    /// Absolute file URL for the selected pet's on-disk artwork, if any.
    func artworkURL(for record: PetLibraryRecord) -> URL? {
        switch record.kind {
        case .builtInDefault:
            return nil
        case .petdex:
            guard let sprite = record.spriteFileName else { return nil }
            return AiboPaths.petsDirectory
                .appendingPathComponent(record.relativePath, isDirectory: true)
                .appendingPathComponent(sprite)
        case .staticImage:
            return AiboPaths.petsDirectory.appendingPathComponent(record.relativePath)
        }
    }

    private func upsert(_ record: PetLibraryRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    private func loadFile() -> PetLibraryFile {
        let url = AiboPaths.petLibraryURL
        guard let data = try? Data(contentsOf: url),
              let file = try? PetLibraryCodec.decode(data)
        else {
            return PetLibraryFile()
        }
        return file
    }

    private func persist() {
        let userRecords = records.filter { $0.kind != .builtInDefault }
        let file = PetLibraryFile(selectedID: selectedID, records: userRecords)
        do {
            try FileManager.default.createDirectory(
                at: AiboPaths.petsDirectory,
                withIntermediateDirectories: true
            )
            let data = try PetLibraryCodec.encode(file)
            try data.write(to: AiboPaths.petLibraryURL, options: .atomic)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to save pet library")
        }
    }

    private func notifyAppearanceChanged() {
        PetSpriteCache.shared.invalidate(except: selectedID)
        PetPanelController.shared.updateHitTestImage()
        PetPanelController.shared.refreshContent()
    }

    private static func message(for error: PetdexInstallError) -> String {
        switch error {
        case .invalidSlug:
            return String(localized: "Enter a Petdex slug or pet page URL")
        case .notFound(let slug):
            return String(localized: "Pet “\(slug)” was not found on Petdex")
        case .api:
            return String(localized: "Petdex API error")
        case .badURL, .downloadFailed:
            return String(localized: "Failed to download pet assets")
        case .invalidSpritesheet:
            return String(localized: "Unsupported image file")
        case .ioFailed:
            return String(localized: "Failed to save pet files")
        }
    }
}
