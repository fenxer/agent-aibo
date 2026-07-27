import Foundation

/// Shared on-disk locations. `aibo-hook` hardcodes the same paths (it cannot link AiboKit).
public enum AiboPaths: Sendable {
    public static let applicationSupportDirectoryName = "aibo"
    public static let socketFileName = "aibo.sock"
    public static let queueDirectoryName = "queue"

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
}
