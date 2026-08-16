import Foundation

/// Shared on-disk locations. `aibo-hook` hardcodes the same paths (it cannot link AiboKit).
public enum AiboPaths: Sendable {
    public static let applicationSupportDirectoryName = "aibo"
    public static let socketFileName = "aibo.sock"
    public static let queueDirectoryName = "queue"
    public static let receiveLogFileName = "receive-log.jsonl"
    public static let ingestLogFileName = "ingest-log.jsonl"

    public static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }

    public static var socketURL: URL {
        applicationSupportDirectory.appendingPathComponent(socketFileName, isDirectory: false)
    }

    public static var queueDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(queueDirectoryName, isDirectory: true)
    }

    public static var receiveLogURL: URL {
        applicationSupportDirectory.appendingPathComponent(receiveLogFileName, isDirectory: false)
    }

    public static var ingestLogURL: URL {
        applicationSupportDirectory.appendingPathComponent(ingestLogFileName, isDirectory: false)
    }

    /// Pre-rename folder. `migrateLegacyLibraryDirectoryIfNeeded` moves this to `aibos`.
    public static let legacyPetsDirectoryName = "pets"
    public static let aibosDirectoryName = "aibos"
    public static let libraryFileName = "library.json"
    public static let petdexDirectoryName = "petdex"
    public static let staticDirectoryName = "static"

    public static var aibosDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(aibosDirectoryName, isDirectory: true)
    }

    public static var libraryURL: URL {
        aibosDirectory.appendingPathComponent(libraryFileName, isDirectory: false)
    }

    public static var petdexDirectory: URL {
        aibosDirectory.appendingPathComponent(petdexDirectoryName, isDirectory: true)
    }

    public static var staticDirectory: URL {
        aibosDirectory.appendingPathComponent(staticDirectoryName, isDirectory: true)
    }

    public static func petdexAiboDirectory(slug: String) -> URL {
        petdexDirectory.appendingPathComponent(slug, isDirectory: true)
    }

    /// Moves `Application Support/aibo/pets` → `aibos` once. No-op if the new folder already exists.
    public static func migrateLegacyLibraryDirectoryIfNeeded() {
        migrateLegacyLibraryDirectory(in: applicationSupportDirectory)
    }

    /// Testable migrate: `…/<support>/pets` → `…/<support>/aibos`.
    public static func migrateLegacyLibraryDirectory(
        in applicationSupport: URL,
        fileManager: FileManager = .default
    ) {
        let destination = applicationSupport.appendingPathComponent(aibosDirectoryName, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(legacyPetsDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        do {
            try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacy, to: destination)
        } catch {
            // Leave the legacy folder in place; the next launch can retry.
        }
    }
}
