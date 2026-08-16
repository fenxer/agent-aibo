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
        let fileManager = FileManager.default
        let extractRoot = fileManager.temporaryDirectory
            .appendingPathComponent("aibo-local-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractRoot) }

        try extractZip(archive, to: extractRoot)
        return try installPack(fromDirectory: extractRoot, fallbackSlug: archive.deletingPathExtension().lastPathComponent)
    }

    /// Testable pack install from an already-expanded folder.
    public static func installPack(
        fromDirectory directory: URL,
        fallbackSlug: String
    ) throws -> AiboLibraryRecord {
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

        let spriteFileName = spriteURL.lastPathComponent
        let record = AiboLibraryRecord(
            id: "petdex.\(slug)",
            kind: .petdex,
            displayName: displayName(from: petJSON, slug: slug),
            relativePath: "\(AiboPaths.petdexDirectoryName)/\(slug)",
            slug: slug,
            spriteFileName: spriteFileName,
            spriteVersionNumber: petJSON.spriteVersionNumber,
            installedAt: Date(),
            installSource: "Local"
        )

        do {
            try PetdexPackStore.writeAtomically(
                destination: AiboPaths.petdexAiboDirectory(slug: slug),
                petJSONData: petJSONData,
                spriteData: spriteData,
                spriteFileName: spriteFileName
            )
        } catch {
            throw LocalAiboImportError.ioFailed
        }
        return record
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

    private static func resolveSpritesheet(petJSON: PetdexPetJSON, in directory: URL) throws -> URL {
        if let raw = petJSON.spritesheetPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return try resolvedFile(named: raw, in: directory)
        }
        for name in ["spritesheet.webp", "spritesheet.png"] {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw LocalAiboImportError.invalidPack
    }

    private static func resolvedFile(named relativePath: String, in directory: URL) throws -> URL {
        let root = directory.standardizedFileURL
        let candidate = directory.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path
        let candidatePath = candidate.path
        let isInside = candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        guard isInside, FileManager.default.fileExists(atPath: candidatePath) else {
            throw LocalAiboImportError.invalidPack
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
