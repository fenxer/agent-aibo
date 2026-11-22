import AiboCore
import Foundation

/// Append-only JSONL receive log under Application Support.
public enum ReceiveLogStore {
    /// Soft cap on disk; oldest lines are dropped beyond this.
    public static let diskMaxEntries = 5_000
    /// How many newest entries the UI should keep in memory.
    public static let uiDisplayLimit = 200

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

    /// Newest-first. Pass `limit` to only decode the newest N lines (for UI).
    public static func load(
        url: URL = AiboPaths.receiveLogURL,
        limit: Int? = nil,
        fileManager: FileManager = .default
    ) throws -> [ReceiveLogEntry] {
        try loadWithCount(url: url, limit: limit, fileManager: fileManager).entries
    }

    /// Reads the log once and returns both newest-first entries (up to `limit`) and the total line count.
    public static func loadWithCount(
        url: URL = AiboPaths.receiveLogURL,
        limit: Int? = nil,
        fileManager: FileManager = .default
    ) throws -> (entries: [ReceiveLogEntry], totalCount: Int) {
        let lines = try readLines(url: url, fileManager: fileManager)
        let selected: ArraySlice<Data>
        if let limit, limit > 0 {
            selected = lines.suffix(limit)
        } else {
            selected = lines[...]
        }

        var entries: [ReceiveLogEntry] = []
        entries.reserveCapacity(selected.count)
        for lineData in selected {
            if let entry = try? decoder.decode(ReceiveLogEntry.self, from: lineData) {
                entries.append(entry)
            }
        }
        return (entries.reversed(), lines.count)
    }

    public static func count(
        url: URL = AiboPaths.receiveLogURL,
        fileManager: FileManager = .default
    ) throws -> Int {
        try readLines(url: url, fileManager: fileManager).count
    }

    public static func append(
        _ entry: ReceiveLogEntry,
        url: URL = AiboPaths.receiveLogURL,
        maxEntries: Int = diskMaxEntries,
        knownLineCount: Int? = nil,
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

        if let knownLineCount {
            let over = knownLineCount - maxEntries
            if over > 0, over.isMultiple(of: 100) {
                try trimIfNeeded(url: url, maxEntries: maxEntries, fileManager: fileManager)
            }
        } else {
            try trimIfNeeded(url: url, maxEntries: maxEntries, fileManager: fileManager)
        }
    }

    public static func clear(
        url: URL = AiboPaths.receiveLogURL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Pretty JSON array of **all** disk entries, newest first — for Export.
    public static func exportJSON(
        url: URL = AiboPaths.receiveLogURL,
        fileManager: FileManager = .default
    ) throws -> Data {
        let entries = try load(url: url, limit: nil, fileManager: fileManager)
        let exportEncoder = JSONEncoder()
        exportEncoder.dateEncodingStrategy = .iso8601
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try exportEncoder.encode(entries)
    }

    private static func readLines(
        url: URL,
        fileManager: FileManager
    ) throws -> [Data] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    }

    private static func trimIfNeeded(
        url: URL,
        maxEntries: Int,
        fileManager: FileManager
    ) throws {
        guard maxEntries > 0 else { return }
        let lines = try readLines(url: url, fileManager: fileManager)
        guard lines.count > maxEntries else { return }

        let kept = lines.suffix(maxEntries)
        var output = Data()
        output.reserveCapacity(kept.reduce(0) { $0 + $1.count + 1 })
        for line in kept {
            output.append(line)
            output.append(UInt8(ascii: "\n"))
        }
        try output.write(to: url, options: .atomic)
    }
}
