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
    private(set) var pendingNamedImport: PendingNamedAiboImport?

    private let installer = PetdexInstaller()
    private var builtInHidden = false
    private var persistedBuiltInRecord = AiboLibraryRecord.builtInDefault

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
        migrateGlobalBubbleLayoutIfNeeded()
        migrateGlobalAiboScaleIfNeeded()
        let selected = selectedRecord
        Task { await convertPetdexClipsIfNeeded(selected) }
    }

    func reloadFromDisk() {
        let file = loadFile()
        let snap = AiboLibraryCodec.snapshot(from: file)
        selectedID = snap.selectedID
        records = snap.records.map { backfillMetadata($0) }
        builtInHidden = snap.builtInHidden
        if let saved = file.records.first(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            persistedBuiltInRecord = savedBuiltInRecord(from: saved)
        } else if let visible = snap.records.first(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            persistedBuiltInRecord = visible
        } else {
            persistedBuiltInRecord = .builtInDefault
        }
    }

    func setBubblePlacement(_ placement: BubblePlacement) {
        guard let index = records.firstIndex(where: { $0.id == selectedID }) else { return }
        guard records[index].bubblePlacement != placement else { return }
        records[index].bubblePlacement = placement
        if selectedID == AiboLibraryDefaults.builtInID {
            persistedBuiltInRecord.bubblePlacement = placement
        }
        persist()
        AiboPanelController.shared.refreshContent()
    }

    func setBubbleDistance(_ distance: Double) {
        let clamped = AiboLibraryRecord.clampedBubbleDistance(distance)
        guard let index = records.firstIndex(where: { $0.id == selectedID }) else { return }
        guard records[index].bubbleDistance != clamped else { return }
        records[index].bubbleDistance = clamped
        if selectedID == AiboLibraryDefaults.builtInID {
            persistedBuiltInRecord.bubbleDistance = clamped
        }
        persist()
        AiboPanelController.shared.refreshContent()
    }

    func setScalePercent(_ percent: Double) {
        guard let index = records.firstIndex(where: { $0.id == selectedID }) else { return }
        var adjusted = AiboLibraryRecord.clampedScalePercent(percent)
        if records[index].pixelOptimizationEnabled {
            let steps = AiboSpriteDisplay.pixelOptimizationPercents(
                for: records[index],
                backingScale: NSScreen.main?.backingScaleFactor ?? 2
            )
            adjusted = AppSettings.snapAiboScalePercentToPixelSteps(adjusted, steps: steps)
        }
        guard records[index].scalePercent != adjusted else { return }
        records[index].scalePercent = adjusted
        if selectedID == AiboLibraryDefaults.builtInID {
            persistedBuiltInRecord.scalePercent = adjusted
        }
        persist()
        AiboPanelController.shared.updateHitTestImage()
        AiboPanelController.shared.refreshContent()
    }

    func setPixelOptimizationEnabled(_ enabled: Bool) {
        guard let index = records.firstIndex(where: { $0.id == selectedID }) else { return }
        guard records[index].pixelOptimizationEnabled != enabled else { return }
        records[index].pixelOptimizationEnabled = enabled
        if enabled {
            let steps = AiboSpriteDisplay.pixelOptimizationPercents(
                for: records[index],
                backingScale: NSScreen.main?.backingScaleFactor ?? 2
            )
            let snapped = AppSettings.snapAiboScalePercentToPixelSteps(
                records[index].scalePercent,
                steps: steps
            )
            records[index].scalePercent = snapped
        }
        if selectedID == AiboLibraryDefaults.builtInID {
            persistedBuiltInRecord.pixelOptimizationEnabled = records[index].pixelOptimizationEnabled
            persistedBuiltInRecord.scalePercent = records[index].scalePercent
        }
        persist()
        AiboSpriteCache.shared.invalidateRecord(selectedID)
        AiboAppearance.invalidateDominantColorCache()
        AiboPanelController.shared.updateHitTestImage()
        AiboPanelController.shared.refreshContent()
    }

    func select(id: String) {
        guard records.contains(where: { $0.id == id }), id != selectedID else { return }
        let fromID = selectedID
        let fromRecord = selectedRecord
        let backing = AiboPanelController.shared.spriteBackingScale
        let fromDesktopSize = AiboSpriteDisplay.desktopSize(
            for: fromRecord,
            nominal: AiboSpriteDisplay.basePointSize * CGFloat(fromRecord.scalePercent / 100),
            backingScale: backing
        )
        selectedID = id
        let toRecord = selectedRecord
        let toDesktopSize = AiboSpriteDisplay.desktopSize(
            for: toRecord,
            nominal: AiboSpriteDisplay.basePointSize * CGFloat(toRecord.scalePercent / 100),
            backingScale: backing
        )
        AiboSwitchSignal.shared.emit(
            from: fromID,
            to: id,
            fromDesktopSize: fromDesktopSize,
            toDesktopSize: toDesktopSize
        )
        persist()
        notifyAppearanceChanged()
        Task { await convertPetdexClipsIfNeeded(selectedRecord) }
    }

    func rename(id: String, to rawName: String) -> AiboRenameOutcome {
        guard let name = AiboLibraryNaming.normalizedDisplayName(rawName),
              let index = records.firstIndex(where: { $0.id == id })
        else { return .unchanged }
        if records[index].displayName == name { return .unchanged }
        if let existing = AiboLibraryNaming.collidingRecord(
            slug: nil,
            displayName: name,
            in: records,
            excludingID: id
        ) {
            return .nameTaken(
                existingDisplayName: existing.displayName,
                suggestedDisplayName: AiboLibraryNaming.suggestedCopyDisplayName(
                    base: name,
                    existingNames: records.map(\.displayName)
                )
            )
        }
        records[index].displayName = name
        if id == AiboLibraryDefaults.builtInID {
            persistedBuiltInRecord.displayName = name
        }
        persist()
        return .renamed
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
        pendingNamedImport = nil
        defer { isInstalling = false }

        switch LocalAiboImporter.classify(url: sourceURL) {
        case .staticImage:
            importStaticImage(from: sourceURL, displayName: displayName)
        case .zipArchive:
            do {
                let payload = try await Task.detached {
                    try LocalAiboImporter.loadPack(fromArchive: sourceURL)
                }.value
                if let existing = AiboLibraryNaming.collidingRecord(
                    slug: payload.slug,
                    displayName: payload.displayName,
                    in: records
                ) {
                    pendingNamedImport = PendingNamedAiboImport(
                        payload: payload,
                        existingDisplayName: existing.displayName,
                        suggestedDisplayName: AiboLibraryNaming.suggestedCopyDisplayName(
                            base: payload.displayName,
                            existingNames: records.map(\.displayName)
                        )
                    )
                    return
                }
                try await finishLocalPackImport(payload)
            } catch let error as LocalAiboImportError {
                lastErrorMessage = Self.message(for: error)
            } catch {
                lastErrorMessage = String(localized: "Failed to install aibo")
            }
        case nil:
            lastErrorMessage = String(localized: "This file isn’t a supported image or Petdex pack")
        }
    }

    func canConfirmPendingNamedImport(displayName: String) -> Bool {
        guard pendingNamedImport != nil,
              let name = AiboLibraryNaming.normalizedDisplayName(displayName)
        else { return false }
        return AiboLibraryNaming.collidingRecord(slug: nil, displayName: name, in: records) == nil
    }

    func cancelPendingNamedImport() {
        pendingNamedImport = nil
    }

    func confirmPendingNamedImport(displayName: String) async {
        guard !isInstalling, let pending = pendingNamedImport else { return }
        guard let name = AiboLibraryNaming.normalizedDisplayName(displayName),
              canConfirmPendingNamedImport(displayName: name)
        else { return }
        let takenSlugs = Set(records.compactMap(\.slug))
        guard let slug = LocalAiboImporter.uniqueSlug(
            preferredDisplayName: name,
            originalSlug: pending.payload.slug,
            takenSlugs: takenSlugs
        ) else { return }

        pendingNamedImport = nil
        isInstalling = true
        lastErrorMessage = nil
        defer { isInstalling = false }

        do {
            try await finishLocalPackImport(pending.payload, slug: slug, displayName: name)
        } catch let error as LocalAiboImportError {
            lastErrorMessage = Self.message(for: error)
        } catch {
            lastErrorMessage = String(localized: "Failed to install aibo")
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

    /// Opens this aibo's folder in Finder. Built-in Poli lives in the app bundle and is skipped.
    func revealInFinder(_ record: AiboLibraryRecord) {
        guard record.revealsOnDiskFolder else { return }
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

    private func finishLocalPackImport(
        _ payload: LocalAiboPackPayload,
        slug: String? = nil,
        displayName: String? = nil
    ) async throws {
        let record = try await Task.detached {
            try LocalAiboImporter.commit(payload, slug: slug, displayName: displayName)
        }.value
        upsert(record)
        selectedID = record.id
        persist()
        notifyAppearanceChanged()
        await convertPetdexClipsIfNeeded(record)
    }

    private func upsert(_ record: AiboLibraryRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            var merged = record
            let existing = records[index]
            merged.installedAt = existing.installedAt ?? record.installedAt
            merged.installSource = existing.installSource ?? record.installSource
            merged.bubblePlacement = existing.bubblePlacement
            merged.bubbleDistance = existing.bubbleDistance
            merged.scalePercent = existing.scalePercent
            merged.pixelOptimizationEnabled = existing.pixelOptimizationEnabled
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

    private func savedBuiltInRecord(from saved: AiboLibraryRecord) -> AiboLibraryRecord {
        var record = AiboLibraryRecord.builtInDefault
        if let name = AiboLibraryNaming.normalizedDisplayName(saved.displayName) {
            record.displayName = name
        }
        record.bubblePlacement = saved.bubblePlacement
        record.bubbleDistance = saved.bubbleDistance
        record.scalePercent = saved.scalePercent
        record.pixelOptimizationEnabled = saved.pixelOptimizationEnabled
        return record
    }

    /// One-shot: copy the former global Position/Distance onto every existing aibo so the current look doesn't jump.
    private func migrateGlobalBubbleLayoutIfNeeded() {
        let defaults = UserDefaults.standard
        let flag = "settings.migratedBubbleLayoutToLibrary"
        guard defaults.object(forKey: flag) == nil else { return }

        let placement = BubblePlacement(
            rawValue: defaults.string(forKey: "settings.bubblePlacement") ?? ""
        ) ?? .top
        let distance: Double
        if defaults.object(forKey: "settings.bubbleDistance") != nil {
            distance = AiboLibraryRecord.clampedBubbleDistance(
                defaults.double(forKey: "settings.bubbleDistance")
            )
        } else {
            distance = AiboLibraryRecord.defaultBubbleDistance
        }

        let hasCustom = placement != .top || distance != AiboLibraryRecord.defaultBubbleDistance
        if hasCustom {
            for index in records.indices {
                records[index].bubblePlacement = placement
                records[index].bubbleDistance = distance
            }
            persistedBuiltInRecord.bubblePlacement = placement
            persistedBuiltInRecord.bubbleDistance = distance
            persist()
        }
        defaults.set(true, forKey: flag)
    }

    /// One-shot: copy the former global Aibo Size / Pixel Optimization onto every existing aibo.
    private func migrateGlobalAiboScaleIfNeeded() {
        let defaults = UserDefaults.standard
        let flag = "settings.migratedAiboScaleToLibrary"
        guard defaults.object(forKey: flag) == nil else { return }

        let scaleKey = defaults.object(forKey: "settings.aiboScalePercent") != nil
            ? "settings.aiboScalePercent"
            : "settings.petScalePercent"
        let scale: Double
        if defaults.object(forKey: scaleKey) != nil {
            scale = AiboLibraryRecord.clampedScalePercent(defaults.double(forKey: scaleKey))
        } else {
            scale = AiboLibraryRecord.defaultScalePercent
        }
        let pixelOpt = defaults.bool(forKey: "settings.pixelOptimizationEnabled")
        let hasCustom = scale != AiboLibraryRecord.defaultScalePercent || pixelOpt
        if hasCustom {
            for index in records.indices {
                records[index].scalePercent = scale
                records[index].pixelOptimizationEnabled = pixelOpt
            }
            persistedBuiltInRecord.scalePercent = scale
            persistedBuiltInRecord.pixelOptimizationEnabled = pixelOpt
            persist()
        }
        defaults.set(true, forKey: flag)
    }

    private func persist() {
        var source = records
        if builtInHidden, !source.contains(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            source.insert(persistedBuiltInRecord, at: 0)
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
        var keep: Set<String> = [selectedID]
        if AiboSwitchSignal.shared.locksDesktopSize {
            keep.insert(AiboSwitchSignal.shared.fromID)
        }
        AiboSpriteCache.shared.invalidate(keeping: keep)
        AiboPanelController.shared.updateHitTestImage()
        // emit() already synced the morph canvas; another deferred resize
        // here would relayout the transparent panel under an empty Metal frame.
        if !AiboSwitchSignal.shared.locksDesktopSize {
            AiboPanelController.shared.refreshContent()
        }
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
        if record.id == selectedID, !AiboSwitchSignal.shared.locksDesktopSize {
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

struct PendingNamedAiboImport: Sendable {
    var payload: LocalAiboPackPayload
    var existingDisplayName: String
    var suggestedDisplayName: String
}
