import AiboCore
import Foundation

/// One offline-queued hook line, with enqueue time parsed from the filename when possible.
public struct QueuedHookLine: Sendable, Equatable {
    public var line: String
    /// From filename `{epoch}-{uuid}.json` written by `aibo-hook` / `enqueue`.
    public var queuedAt: Date?
    public var filename: String

    public init(line: String, queuedAt: Date?, filename: String) {
        self.line = line
        self.queuedAt = queuedAt
        self.filename = filename
    }
}

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

    /// Drains the offline queue oldest-first and deletes each file.
    public static func drain(
        fileManager: FileManager = .default
    ) throws -> [QueuedHookLine] {
        try ensureDirectories(fileManager: fileManager)
        let urls = try fileManager.contentsOfDirectory(
            at: AiboPaths.queueDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var items: [QueuedHookLine] = []
        for url in urls {
            let filename = url.lastPathComponent
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .newlines)
                if !trimmed.isEmpty {
                    items.append(
                        QueuedHookLine(
                            line: trimmed,
                            queuedAt: queuedAt(fromFilename: filename),
                            filename: filename
                        )
                    )
                }
            }
            try? fileManager.removeItem(at: url)
        }
        return items
    }

    /// Parses `{epoch}-{uuid}.json` filenames produced by enqueue / aibo-hook.
    public static func queuedAt(fromFilename filename: String) -> Date? {
        let base = (filename as NSString).deletingPathExtension
        guard let dash = base.firstIndex(of: "-") else { return nil }
        let prefix = String(base[..<dash])
        guard let interval = TimeInterval(prefix) else { return nil }
        return Date(timeIntervalSince1970: interval)
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
