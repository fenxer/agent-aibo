import AiboCore
import Foundation

public enum AntigravityHooksFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("hooks.json", isDirectory: false)
    }

    public static func install(
        binaryPath: String,
        url: URL = defaultURL,
        fileManager: FileManager = .default
    ) throws {
        let config = try readObject(from: url, fileManager: fileManager)
        let next = AntigravityHooksInstaller.install(config: config, binaryPath: binaryPath)
        try writeAtomic(next, to: url, fileManager: fileManager)
    }

    public static func uninstall(
        url: URL = defaultURL,
        fileManager: FileManager = .default
    ) throws {
        let config = try readObject(from: url, fileManager: fileManager)
        let next = AntigravityHooksInstaller.uninstall(config: config)
        try writeAtomic(next, to: url, fileManager: fileManager)
    }

    public static func isInstalled(
        url: URL = defaultURL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let config = try readObject(from: url, fileManager: fileManager)
        return AntigravityHooksInstaller.isInstalled(config)
    }

    /// Missing file is an empty config. A file that exists but is not a JSON
    /// object throws, so install never overwrites it.
    private static func readObject(
        from url: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        if !fileManager.fileExists(atPath: url.path) {
            return [:]
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return try HooksConfigJSON.parseObject(from: data)
    }

    private static func writeAtomic(
        _ config: [String: Any],
        to url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try HooksConfigJSON.encodePretty(config)
        try data.write(to: url, options: .atomic)
    }
}
