import AiboCore
import Foundation

public enum HookQueue {
    public static let maxFileCount = 200
    public static let maxTotalBytes = 5 * 1024 * 1024

    public static func ensureDirectories(
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: AiboPaths.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: AiboPaths.queueDirectory,
            withIntermediateDirectories: true
        )
    }

    public static func enqueue(
        line: String,
        fileManager: FileManager = .default,
        now: Date = Date(),
        uuid: UUID = UUID()
    ) throws {
        try ensureDirectories(fileManager: fileManager)
        try trimIfNeeded(fileManager: fileManager)

        let filename = String(format: "%.6f-%@.json", now.timeIntervalSince1970, uuid.uuidString)
        let url = AiboPaths.queueDirectory.appendingPathComponent(filename)
        var payload = line
        if !payload.hasSuffix("\n") {
            payload.append("\n")
        }
        try Data(payload.utf8).write(to: url, options: .atomic)
    }

    public static func drain(
        fileManager: FileManager = .default
    ) throws -> [String] {
        try ensureDirectories(fileManager: fileManager)
        let urls = try fileManager.contentsOfDirectory(
            at: AiboPaths.queueDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var lines: [String] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .newlines)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }
            try? fileManager.removeItem(at: url)
        }
        return lines
    }

    public static func trimIfNeeded(fileManager: FileManager = .default) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: AiboPaths.queueDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var total = 0
        for url in urls {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            total += values.fileSize ?? 0
        }

        var mutable = urls
        while mutable.count > maxFileCount || total > maxTotalBytes {
            guard let oldest = mutable.first else { break }
            let values = try oldest.resourceValues(forKeys: [.fileSizeKey])
            total -= values.fileSize ?? 0
            try? fileManager.removeItem(at: oldest)
            mutable.removeFirst()
        }
    }
}
