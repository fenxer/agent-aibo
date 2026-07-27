import AiboCore
import Foundation

public enum CursorHooksFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("hooks.json", isDirectory: false)
    }

    public static func install(
        command: String,
        url: URL = defaultURL,
        fileManager: FileManager = .default
    ) throws {
        let config = try readObject(from: url, fileManager: fileManager)
        let next = try CursorHooksInstaller.install(config: config, command: command)
        try writeAtomic(next, to: url, fileManager: fileManager)
    }

    public static func uninstall(
        url: URL = defaultURL,
        fileManager: FileManager = .default
    ) throws {
        let config = try readObject(from: url, fileManager: fileManager)
        let next = try CursorHooksInstaller.uninstall(config: config)
        try writeAtomic(next, to: url, fileManager: fileManager)
    }

    public static func isInstalled(
        url: URL = defaultURL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let config = try readObject(from: url, fileManager: fileManager)
        return CursorHooksInstaller.isInstalled(config)
    }

    private static func readObject(
        from url: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        if !fileManager.fileExists(atPath: url.path) {
            return [:]
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return try CursorHooksInstaller.parseObject(from: data)
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
        let data = try CursorHooksInstaller.encodePretty(config)
        try data.write(to: url, options: .atomic)
    }
}
