import Foundation

/// On-disk Aibo sprite pack: `aibo.json` plus per-state PNG clips.
///
/// Petdex downloads are sliced into this layout at install time so playback
/// can load one state at a time instead of keeping the whole atlas decoded.
public struct AiboSpritePackManifest: Codable, Sendable, Equatable {
    public static let formatIdentifier = "aibo"
    public static let currentFormatVersion = 1
    public static let currentSliceVersion = 1

    public var format: String
    public var formatVersion: Int
    public var sliceVersion: Int
    public var extends: String?
    public var cellWidth: Int
    public var cellHeight: Int
    public var clips: [String: AiboSpriteClip]
    public var look: [AiboSpriteLookFrame]

    enum CodingKeys: String, CodingKey {
        case format
        case formatVersion
        case sliceVersion
        case `extends`
        case cellWidth
        case cellHeight
        case clips
        case look
    }

    public init(
        format: String = formatIdentifier,
        formatVersion: Int = currentFormatVersion,
        sliceVersion: Int = currentSliceVersion,
        extends: String? = nil,
        cellWidth: Int,
        cellHeight: Int,
        clips: [String: AiboSpriteClip],
        look: [AiboSpriteLookFrame] = []
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.sliceVersion = sliceVersion
        self.extends = extends
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.clips = clips
        self.look = look
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        sliceVersion = try container.decode(Int.self, forKey: .sliceVersion)
        extends = try container.decodeIfPresent(String.self, forKey: .extends)
        cellWidth = try container.decode(Int.self, forKey: .cellWidth)
        cellHeight = try container.decode(Int.self, forKey: .cellHeight)
        clips = try container.decode([String: AiboSpriteClip].self, forKey: .clips)
        look = try container.decodeIfPresent([AiboSpriteLookFrame].self, forKey: .look) ?? []
    }
}

public struct AiboSpriteClip: Codable, Sendable, Equatable {
    public var file: String
    public var frames: Int
    public var durationMilliseconds: Int?

    public init(file: String, frames: Int, durationMilliseconds: Int? = nil) {
        self.file = file
        self.frames = frames
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct AiboSpriteLookFrame: Codable, Sendable, Equatable {
    public var index: Int
    public var file: String

    public init(index: Int, file: String) {
        self.index = index
        self.file = file
    }
}

public enum AiboSpritePack: Sendable {
    public static let manifestFileName = "aibo.json"
    public static let clipsDirectoryName = "clips"

    public static func directory(for record: AiboLibraryRecord) -> URL? {
        guard record.kind == .petdex, !record.relativePath.isEmpty else { return nil }
        return AiboPaths.aibosDirectory.appendingPathComponent(record.relativePath, isDirectory: true)
    }

    public static func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent(manifestFileName, isDirectory: false)
    }

    public static func clipsDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent(clipsDirectoryName, isDirectory: true)
    }

    public static func clipRelativePath(state: PetdexSpriteState) -> String {
        "\(clipsDirectoryName)/\(state.rawValue).png"
    }

    public static func lookRelativePath(index: Int) -> String {
        "\(clipsDirectoryName)/look-\(String(format: "%02d", index)).png"
    }

    public static func loadManifest(in directory: URL) -> AiboSpritePackManifest? {
        guard let data = try? Data(contentsOf: manifestURL(in: directory)),
              let manifest = try? JSONDecoder().decode(AiboSpritePackManifest.self, from: data),
              manifest.format == AiboSpritePackManifest.formatIdentifier,
              manifest.formatVersion == AiboSpritePackManifest.currentFormatVersion,
              manifest.cellWidth > 0,
              manifest.cellHeight > 0,
              manifest.clips[PetdexSpriteState.idle.rawValue] != nil
        else { return nil }
        return manifest
    }

    public static func isComplete(_ manifest: AiboSpritePackManifest, in directory: URL) -> Bool {
        guard let idle = manifest.clips[PetdexSpriteState.idle.rawValue],
              idle.frames >= 1,
              resolveExistingFile(named: idle.file, in: directory) != nil
        else { return false }
        for clip in manifest.clips.values {
            guard clip.frames >= 1,
                  resolveExistingFile(named: clip.file, in: directory) != nil
            else { return false }
        }
        if !manifest.look.isEmpty, manifest.look.count != PetdexLookDirection.count {
            return false
        }
        var seen: Set<Int> = []
        for frame in manifest.look {
            guard (0..<PetdexLookDirection.count).contains(frame.index),
                  seen.insert(frame.index).inserted,
                  resolveExistingFile(named: frame.file, in: directory) != nil
            else { return false }
        }
        return true
    }

    public static func idlePreviewURL(in directory: URL) -> URL? {
        guard let manifest = loadManifest(in: directory),
              isComplete(manifest, in: directory),
              let idle = manifest.clips[PetdexSpriteState.idle.rawValue]
        else { return nil }
        return resolveExistingFile(named: idle.file, in: directory)
    }

    public static func spritesheetURL(in directory: URL, preferredFileName: String? = nil) -> URL? {
        if let preferredFileName,
           let url = resolveExistingFile(named: preferredFileName, in: directory)
        {
            return url
        }
        let petJSONURL = directory.appendingPathComponent("pet.json", isDirectory: false)
        if let data = try? Data(contentsOf: petJSONURL),
           let petJSON = try? PetdexInstallAPI.decodePetJSON(data),
           let path = petJSON.spritesheetPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let url = resolveExistingFile(named: path, in: directory)
        {
            return url
        }
        for name in ["spritesheet.webp", "spritesheet.png"] {
            if let url = resolveExistingFile(named: name, in: directory) {
                return url
            }
        }
        return nil
    }

    public static func resolveExistingFile(named relativePath: String, in directory: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let root = directory.standardizedFileURL
        let candidate = directory.appendingPathComponent(trimmed).standardizedFileURL
        let rootPath = root.path
        let candidatePath = candidate.path
        let isInside = candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        guard isInside, FileManager.default.fileExists(atPath: candidatePath) else { return nil }
        return candidate
    }
}
