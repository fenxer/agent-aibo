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
        var payload = line
        if !payload.hasSuffix("\n") {
            payload.append("\n")
        }
        let payloadData = Data(payload.utf8)
        guard payloadData.count <= maxTotalBytes else { return }
        try trimIfNeeded(fileManager: fileManager, reservingBytes: payloadData.count)

        let filename = String(format: "%.6f-%@.json", now.timeIntervalSince1970, uuid.uuidString)
        let url = AiboPaths.queueDirectory.appendingPathComponent(filename)
        try payloadData.write(to: url, options: .atomic)
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
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                // `aibo-hook` may concurrently trim the oldest file while draining; skip missing files.
                if isFileNotFound(error) { continue }
                throw error
            }
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

    public static func trimIfNeeded(
        fileManager: FileManager = .default,
        reservingBytes incomingBytes: Int = 0
    ) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: AiboPaths.queueDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var total = incomingBytes
        var sizes: [URL: Int] = [:]
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            sizes[url] = size
            total += size
        }

        let fileLimit = incomingBytes > 0 ? maxFileCount - 1 : maxFileCount
        var mutable = urls
        while mutable.count > fileLimit || total > maxTotalBytes {
            guard let oldest = mutable.first else { break }
            total -= sizes[oldest] ?? 0
            try? fileManager.removeItem(at: oldest)
            mutable.removeFirst()
        }
    }

    private static func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT) {
            return true
        }
        return false
    }
}
