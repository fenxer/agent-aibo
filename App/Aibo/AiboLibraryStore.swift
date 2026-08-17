import AiboCore
import AppKit
import Foundation

@MainActor
@Observable
final class AiboLibraryStore {
    static let shared = AiboLibraryStore()

    private(set) var records: [AiboLibraryRecord] = [.builtInDefault]
    private(set) var selectedID: String = AiboLibraryDefaults.builtInID
    private(set) var lastErrorMessage: String?
    private(set) var isInstalling = false

    private let installer = PetdexInstaller()
    private var builtInHidden = false
    private var persistedBuiltInDisplayName = AiboLibraryDefaults.builtInDisplayName

    var selectedRecord: AiboLibraryRecord {
        records.first(where: { $0.id == selectedID }) ?? .builtInDefault
    }

    /// Allocated size of `AiboPaths.aibosDirectory` (installed aibos + `library.json`).
    func occupiedDiskBytes() -> Int64 {
        allocatedSize(at: AiboPaths.aibosDirectory)
    }

    func occupiedDiskBytes(for record: AiboLibraryRecord) -> Int64 {
        switch record.kind {
        case .builtInDefault:
            return 0
        case .petdex, .staticImage:
            guard !record.relativePath.isEmpty else { return 0 }
            return allocatedSize(
                at: AiboPaths.aibosDirectory.appendingPathComponent(record.relativePath)
            )
        }
    }

    private func allocatedSize(at root: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]
        guard let values = try? root.resourceValues(forKeys: keys) else { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard values.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: Array(keys),
                  options: [.skipsHiddenFiles]
              )
        else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let fileValues = try? fileURL.resourceValues(forKeys: keys),
                  fileValues.isRegularFile == true
            else { continue }
            total += Int64(fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0)
        }
        return total
    }

    private init() {
        AiboPaths.migrateLegacyLibraryDirectoryIfNeeded()
        reloadFromDisk()
        let selected = selectedRecord
        Task { await convertPetdexClipsIfNeeded(selected) }
    }

    func reloadFromDisk() {
        let file = loadFile()
        let snap = AiboLibraryCodec.snapshot(from: file)
        selectedID = snap.selectedID
        records = snap.records.map { backfillMetadata($0) }
        builtInHidden = snap.builtInHidden
        persistedBuiltInDisplayName = savedBuiltInDisplayName(in: file) ?? snap.records
            .first(where: { $0.id == AiboLibraryDefaults.builtInID })?
            .displayName
            ?? AiboLibraryDefaults.builtInDisplayName
    }

    func select(id: String) {
        guard records.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
        notifyAppearanceChanged()
        Task { await convertPetdexClipsIfNeeded(selectedRecord) }
    }

    func rename(id: String, to rawName: String) {
        guard let name = AiboLibraryNaming.normalizedDisplayName(rawName),
              let index = records.firstIndex(where: { $0.id == id })
        else { return }
        guard records[index].displayName != name else { return }
        records[index].displayName = name
        if id == AiboLibraryDefaults.builtInID {
            persistedBuiltInDisplayName = name
        }
        persist()
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
            await convertPetdexClipsIfNeeded(record)
        } catch let error as PetdexInstallError {
            lastErrorMessage = Self.message(for: error)
        } catch {
            lastErrorMessage = String(localized: "Failed to install aibo")
        }
    }

    func importLocal(from sourceURL: URL, displayName: String? = nil) async {
        guard !isInstalling else { return }
        isInstalling = true
        lastErrorMessage = nil
        defer { isInstalling = false }

        switch LocalAiboImporter.classify(url: sourceURL) {
        case .staticImage:
            importStaticImage(from: sourceURL, displayName: displayName)
        case .zipArchive:
            do {
                let record = try await Task.detached {
                    try LocalAiboImporter.installPack(fromArchive: sourceURL)
                }.value
                upsert(record)
                selectedID = record.id
                persist()
                notifyAppearanceChanged()
                await convertPetdexClipsIfNeeded(record)
            } catch let error as LocalAiboImportError {
                lastErrorMessage = Self.message(for: error)
            } catch {
                lastErrorMessage = String(localized: "Failed to install aibo")
            }
        case nil:
            lastErrorMessage = String(localized: "This file isn’t a supported image or Petdex pack")
        }
    }

    func importStaticImage(from sourceURL: URL, displayName: String? = nil) {
        lastErrorMessage = nil
        do {
            try FileManager.default.createDirectory(
                at: AiboPaths.staticDirectory,
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
            let destination = AiboPaths.staticDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = AiboLibraryRecord(
                id: "static.\(id)",
                kind: .staticImage,
                displayName: (name?.isEmpty == false ? name! : sourceURL.deletingPathExtension().lastPathComponent),
                relativePath: "\(AiboPaths.staticDirectoryName)/\(fileName)",
                installedAt: Date()
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
        remove(ids: [id])
    }

    func remove(ids: some Sequence<String>) {
        guard let toRemoveIDs = AiboLibraryDeletion.idsToRemove(requested: ids, from: records),
              !toRemoveIDs.isEmpty
        else { return }
        let removeIDs = Set(toRemoveIDs)
        let toRemove = records.filter { removeIDs.contains($0.id) }
        if let builtIn = toRemove.first(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            persistedBuiltInDisplayName = builtIn.displayName
            builtInHidden = true
        }
        records.removeAll { removeIDs.contains($0.id) }
        if !records.contains(where: { $0.id == selectedID }) {
            selectedID = records.first?.id ?? AiboLibraryDefaults.builtInID
        }
        for record in toRemove where record.removesOnDiskFiles {
            let absolute = AiboPaths.aibosDirectory.appendingPathComponent(record.relativePath)
            try? FileManager.default.removeItem(at: absolute)
        }
        persist()
        notifyAppearanceChanged()
    }

    /// Opens this aibo's folder in Finder (`aibos/` for Default).
    func revealInFinder(_ record: AiboLibraryRecord) {
        let folder = folderURL(for: record)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func folderURL(for record: AiboLibraryRecord) -> URL {
        switch record.kind {
        case .builtInDefault:
            return AiboPaths.aibosDirectory
        case .petdex:
            return AiboPaths.aibosDirectory.appendingPathComponent(record.relativePath, isDirectory: true)
        case .staticImage:
            return AiboPaths.aibosDirectory
                .appendingPathComponent(record.relativePath)
                .deletingLastPathComponent()
        }
    }

    /// Absolute file URL for the selected aibo's on-disk artwork, if any.
    func artworkURL(for record: AiboLibraryRecord) -> URL? {
        switch record.kind {
        case .builtInDefault:
            return nil
        case .petdex:
            let directory = AiboPaths.aibosDirectory
                .appendingPathComponent(record.relativePath, isDirectory: true)
            if let idle = AiboSpritePack.idlePreviewURL(in: directory) {
                return idle
            }
            if let sprite = record.spriteFileName {
                let url = directory.appendingPathComponent(sprite)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
            return AiboSpritePack.spritesheetURL(
                in: directory,
                preferredFileName: record.spriteFileName
            )
        case .staticImage:
            return AiboPaths.aibosDirectory.appendingPathComponent(record.relativePath)
        }
    }

    private func upsert(_ record: AiboLibraryRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            var merged = record
            let existing = records[index]
            merged.installedAt = existing.installedAt ?? record.installedAt
            merged.installSource = existing.installSource ?? record.installSource
            records[index] = merged
        } else {
            records.append(record)
        }
    }

    /// Fills missing install metadata for aibos saved before those fields existed.
    private func backfillMetadata(_ record: AiboLibraryRecord) -> AiboLibraryRecord {
        guard record.kind != .builtInDefault else { return record }
        var updated = record
        if updated.installedAt == nil {
            updated.installedAt = fileCreationDate(for: record)
        }
        if updated.installSource == nil, record.kind == .petdex, let slug = record.slug {
            updated.installSource = PetdexInstallAPI.petPageURL(slug: slug).absoluteString
        }
        return updated
    }

    private func fileCreationDate(for record: AiboLibraryRecord) -> Date? {
        guard !record.relativePath.isEmpty else { return nil }
        let url = AiboPaths.aibosDirectory.appendingPathComponent(record.relativePath)
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    private func loadFile() -> AiboLibraryFile {
        let url = AiboPaths.libraryURL
        guard let data = try? Data(contentsOf: url),
              let file = try? AiboLibraryCodec.decode(data)
        else {
            return AiboLibraryFile()
        }
        return file
    }

    private func savedBuiltInDisplayName(in file: AiboLibraryFile) -> String? {
        guard let saved = file.records.first(where: { $0.id == AiboLibraryDefaults.builtInID }) else {
            return nil
        }
        return AiboLibraryNaming.normalizedDisplayName(saved.displayName)
    }

    private func persist() {
        var source = records
        if builtInHidden, !source.contains(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            var builtIn = AiboLibraryRecord.builtInDefault
            builtIn.displayName = persistedBuiltInDisplayName
            source.insert(builtIn, at: 0)
        }
        let userRecords = AiboLibraryCodec.persistableRecords(from: source)
        let file = AiboLibraryFile(
            selectedID: selectedID,
            records: userRecords,
            builtInHidden: builtInHidden
        )
        do {
            try FileManager.default.createDirectory(
                at: AiboPaths.aibosDirectory,
                withIntermediateDirectories: true
            )
            let data = try AiboLibraryCodec.encode(file)
            try data.write(to: AiboPaths.libraryURL, options: .atomic)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to save aibo library")
        }
    }

    private func notifyAppearanceChanged() {
        AiboSpriteCache.shared.invalidate(except: selectedID)
        AiboPanelController.shared.updateHitTestImage()
        AiboPanelController.shared.refreshContent()
    }

    /// Slices leftover Petdex atlases for this one aibo. New installs already
    /// convert in the installer; this covers pets added before clip slicing.
    private func convertPetdexClipsIfNeeded(_ record: AiboLibraryRecord) async {
        guard record.kind == .petdex,
              let directory = AiboSpritePack.directory(for: record)
        else { return }
        let outcome = await Task.detached(priority: .utility) {
            PetdexClipSlicer.convertIfNeeded(in: directory)
        }.value
        guard outcome == .converted else { return }
        AiboSpriteCache.shared.invalidateRecord(record.id)
        if record.id == selectedID {
            AiboPanelController.shared.updateHitTestImage()
            AiboPanelController.shared.refreshContent()
        }
    }

    private static func message(for error: PetdexInstallError) -> String {
        switch error {
        case .invalidSlug:
            return String(localized: "Enter a Petdex slug or page URL")
        case .notFound(let slug):
            return String(localized: "“\(slug)” was not found on Petdex")
        case .api:
            return String(localized: "Petdex API error")
        case .badURL, .downloadFailed:
            return String(localized: "Failed to download aibo assets")
        case .invalidSpritesheet:
            return String(localized: "Unsupported image file")
        case .ioFailed:
            return String(localized: "Failed to save aibo files")
        }
    }

    private static func message(for error: LocalAiboImportError) -> String {
        switch error {
        case .unsupportedFile:
            return String(localized: "This file isn’t a supported image or Petdex pack")
        case .invalidPack:
            return String(localized: "This archive isn’t a valid Petdex pack")
        case .ioFailed:
            return String(localized: "Failed to save aibo files")
        }
    }
}
