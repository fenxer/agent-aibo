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

    public static let petsDirectoryName = "pets"
    public static let petLibraryFileName = "library.json"
    public static let petdexPetsDirectoryName = "petdex"
    public static let staticPetsDirectoryName = "static"

    public static var petsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(petsDirectoryName, isDirectory: true)
    }

    public static var petLibraryURL: URL {
        petsDirectory.appendingPathComponent(petLibraryFileName, isDirectory: false)
    }

    public static var petdexPetsDirectory: URL {
        petsDirectory.appendingPathComponent(petdexPetsDirectoryName, isDirectory: true)
    }

    public static var staticPetsDirectory: URL {
        petsDirectory.appendingPathComponent(staticPetsDirectoryName, isDirectory: true)
    }

    public static func petdexPetDirectory(slug: String) -> URL {
        petdexPetsDirectory.appendingPathComponent(slug, isDirectory: true)
    }
}
