import Foundation

public enum LocalAiboImportKind: Sendable, Equatable {
    case staticImage
    case zipArchive
}

public enum LocalAiboImportError: Error, Sendable, Equatable {
    case unsupportedFile
    case invalidPack
    case ioFailed
}

/// Parsed local pack, before writing into the library.
public struct LocalAiboPackPayload: Sendable {
    public var petJSON: PetdexPetJSON
    public var petJSONData: Data
    public var spriteData: Data
    public var spriteFileName: String
    public var slug: String
    public var displayName: String
}

/// Classifies a user-picked file and installs a local Petdex zip into `petdex/<slug>/`.
public enum LocalAiboImporter: Sendable {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "tif", "tiff",
    ]
    public static let archiveExtensions: Set<String> = ["zip"]

    public static func classify(url: URL) -> LocalAiboImportKind? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .staticImage }
        if archiveExtensions.contains(ext) { return .zipArchive }
        return nil
    }

    /// Unzips `archive`, requires `pet.json` + its spritesheet, writes a petdex pack.
    public static func installPack(fromArchive archive: URL) throws -> AiboLibraryRecord {
        try commit(loadPack(fromArchive: archive))
    }

    /// Testable pack install from an already-expanded folder.
    public static func installPack(
        fromDirectory directory: URL,
        fallbackSlug: String
    ) throws -> AiboLibraryRecord {
        try commit(loadPack(fromDirectory: directory, fallbackSlug: fallbackSlug))
    }

    public static func loadPack(fromArchive archive: URL) throws -> LocalAiboPackPayload {
        let fileManager = FileManager.default
        let extractRoot = fileManager.temporaryDirectory
            .appendingPathComponent("aibo-local-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractRoot) }

        try extractZip(archive, to: extractRoot)
        return try loadPack(
            fromDirectory: extractRoot,
            fallbackSlug: archive.deletingPathExtension().lastPathComponent
        )
    }

    public static func loadPack(
        fromDirectory directory: URL,
        fallbackSlug: String
    ) throws -> LocalAiboPackPayload {
        let petJSONURL = try findPetJSON(in: directory)
        let petJSONData = try Data(contentsOf: petJSONURL)
        guard let petJSON = try? PetdexInstallAPI.decodePetJSON(petJSONData) else {
            throw LocalAiboImportError.invalidPack
        }

        let packDirectory = petJSONURL.deletingLastPathComponent()
        let spriteURL = try resolveSpritesheet(petJSON: petJSON, in: packDirectory)
        let spriteData = try Data(contentsOf: spriteURL)
        guard !spriteData.isEmpty else { throw LocalAiboImportError.invalidPack }

        guard let slug = slug(from: petJSON, fallback: fallbackSlug) else {
            throw LocalAiboImportError.invalidPack
        }

        return LocalAiboPackPayload(
            petJSON: petJSON,
            petJSONData: petJSONData,
            spriteData: spriteData,
            spriteFileName: spriteURL.lastPathComponent,
            slug: slug,
            displayName: displayName(from: petJSON, slug: slug)
        )
    }

    public static func commit(
        _ payload: LocalAiboPackPayload,
        slug slugOverride: String? = nil,
        displayName displayNameOverride: String? = nil
    ) throws -> AiboLibraryRecord {
        let slug = slugOverride ?? payload.slug
        guard sanitizeSlug(slug) == slug else {
            throw LocalAiboImportError.invalidPack
        }
        let displayName = AiboLibraryNaming.normalizedDisplayName(displayNameOverride ?? payload.displayName)
            ?? payload.displayName
        let record = AiboLibraryRecord(
            id: "petdex.\(slug)",
            kind: .petdex,
            displayName: displayName,
            relativePath: "\(AiboPaths.petdexDirectoryName)/\(slug)",
            slug: slug,
            spriteFileName: payload.spriteFileName,
            spriteVersionNumber: payload.petJSON.spriteVersionNumber,
            installedAt: Date(),
            installSource: "Local"
        )

        do {
            let destination = AiboPaths.petdexAiboDirectory(slug: slug)
            try PetdexPackStore.writeAtomically(
                destination: destination,
                petJSONData: payload.petJSONData,
                spriteData: payload.spriteData,
                spriteFileName: payload.spriteFileName
            )
            PetdexClipSlicer.convertIfNeeded(in: destination)
        } catch {
            throw LocalAiboImportError.ioFailed
        }
        return record
    }

    /// `preferredName` sanitized if free, otherwise `originalSlug-2`, `-3`, …
    public static func uniqueSlug(
        preferredDisplayName: String,
        originalSlug: String,
        takenSlugs: Set<String>
    ) -> String? {
        if let slug = sanitizeSlug(preferredDisplayName), !takenSlugs.contains(slug) {
            return slug
        }
        var suffix = 2
        while suffix < 10_000 {
            guard let slug = sanitizeSlug("\(originalSlug)-\(suffix)") else { return nil }
            if !takenSlugs.contains(slug) {
                return slug
            }
            suffix += 1
        }
        return nil
    }

    public static func slug(from petJSON: PetdexPetJSON, fallback: String) -> String? {
        if let id = petJSON.id, let slug = sanitizeSlug(id) { return slug }
        return sanitizeSlug(fallback)
    }

    static func sanitizeSlug(_ raw: String) -> String? {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if PetdexSlugParser.isValidSlug(lowered) { return lowered }

        var mapped = ""
        mapped.reserveCapacity(lowered.count)
        for character in lowered {
            if character.isASCII, character.isLetter || character.isNumber || character == "-" {
                mapped.append(character)
            } else {
                mapped.append("-")
            }
        }
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return PetdexSlugParser.isValidSlug(trimmed) ? trimmed : nil
    }

    private static func displayName(from petJSON: PetdexPetJSON, slug: String) -> String {
        let name = petJSON.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? slug : name
    }

    private static func findPetJSON(in root: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LocalAiboImportError.invalidPack
        }

        var found: [(url: URL, depth: Int)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "pet.json" else { continue }
            if fileURL.path.contains("/__MACOSX/") { continue }
            let relative = fileURL.path.dropFirst(root.path.count)
            let depth = relative.split(separator: "/").count
            found.append((fileURL, depth))
        }

        guard let minDepth = found.map(\.depth).min() else {
            throw LocalAiboImportError.invalidPack
        }
        let top = found.filter { $0.depth == minDepth }
        guard top.count == 1, let url = top.first?.url else {
            throw LocalAiboImportError.invalidPack
        }
        return url
    }

    private static let spritesheetFileNames = ["spritesheet.webp", "spritesheet.png"]

    private static func resolveSpritesheet(petJSON: PetdexPetJSON, in directory: URL) throws -> URL {
        if let raw = petJSON.spritesheetPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            if let url = try fileInsideDirectory(named: raw, in: directory) {
                return url
            }
            for alternate in alternateSpritesheetPaths(raw) {
                if let url = try fileInsideDirectory(named: alternate, in: directory) {
                    return url
                }
            }
        }
        for name in spritesheetFileNames {
            if let url = try fileInsideDirectory(named: name, in: directory) {
                return url
            }
        }
        throw LocalAiboImportError.invalidPack
    }

    private static func alternateSpritesheetPaths(_ relativePath: String) -> [String] {
        let ext = (relativePath as NSString).pathExtension
        guard !ext.isEmpty else {
            return ["\(relativePath).webp", "\(relativePath).png"]
        }
        let stem = (relativePath as NSString).deletingPathExtension
        switch ext.lowercased() {
        case "webp":
            return ["\(stem).png"]
        case "png":
            return ["\(stem).webp"]
        default:
            return ["\(stem).png", "\(stem).webp"]
        }
    }

    /// `nil` if missing. Throws when the path escapes `directory`.
    private static func fileInsideDirectory(named relativePath: String, in directory: URL) throws -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.split(separator: "/").contains("..") {
            throw LocalAiboImportError.invalidPack
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private static func extractZip(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--", archive.path, destination.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LocalAiboImportError.invalidPack
        }
        guard process.terminationStatus == 0 else {
            throw LocalAiboImportError.invalidPack
        }
    }
}
