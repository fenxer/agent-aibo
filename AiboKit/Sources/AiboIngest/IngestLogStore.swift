import AiboCore
import Foundation

/// Append-only JSONL hook-ingest log under Application Support (DEBUG diagnostics).
public enum IngestLogStore {
    /// Soft cap on disk; oldest lines are dropped beyond this.
    public static let diskMaxEntries = 2_000

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Newest-first. Pass `limit` to only decode the newest N lines.
    public static func load(
        url: URL = AiboPaths.ingestLogURL,
        limit: Int? = nil,
        fileManager: FileManager = .default
    ) throws -> [IngestLogEntry] {
        let lines = try readLines(url: url, fileManager: fileManager)
        let selected: ArraySlice<Substring>
        if let limit, limit > 0 {
            selected = lines.suffix(limit)
        } else {
            selected = lines[...]
        }

        var entries: [IngestLogEntry] = []
        entries.reserveCapacity(selected.count)
        for line in selected {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let entry = try? decoder.decode(IngestLogEntry.self, from: lineData) {
                entries.append(entry)
            }
        }
        return entries.reversed()
    }

    public static func count(
        url: URL = AiboPaths.ingestLogURL,
        fileManager: FileManager = .default
    ) throws -> Int {
        try readLines(url: url, fileManager: fileManager).count
    }

    public static func append(
        _ entry: IngestLogEntry,
        url: URL = AiboPaths.ingestLogURL,
        maxEntries: Int = diskMaxEntries,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var line = try encoder.encode(entry)
        line.append(UInt8(ascii: "\n"))

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }

        try trimIfNeeded(url: url, maxEntries: maxEntries, fileManager: fileManager)
    }

    public static func clear(
        url: URL = AiboPaths.ingestLogURL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Raw JSONL bytes as currently on disk (oldest → newest) — for Copy / paste.
    public static func exportJSONL(
        url: URL = AiboPaths.ingestLogURL,
        fileManager: FileManager = .default
    ) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else { return Data() }
        return try Data(contentsOf: url)
    }

    private static func readLines(
        url: URL,
        fileManager: FileManager
    ) throws -> [Substring] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private static func trimIfNeeded(
        url: URL,
        maxEntries: Int,
        fileManager: FileManager
    ) throws {
        guard maxEntries > 0 else { return }
        let lines = try readLines(url: url, fileManager: fileManager)
        guard lines.count > maxEntries else { return }

        let kept = lines.suffix(maxEntries).joined(separator: "\n") + "\n"
        try Data(kept.utf8).write(to: url, options: .atomic)
    }
}
