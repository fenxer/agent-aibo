import Darwin
import Foundation

/// Captures the on-disk identity of an executable at launch so a long-lived
/// main process never spawns a mismatched build after an update or Xcode rebuild.
public struct LaunchedExecutable: Sendable, Equatable {
    public struct FileIdentity: Sendable, Equatable {
        public var device: Int32
        public var inode: UInt64
        public var size: Int64
        public var modifiedSeconds: Int
        public var modifiedNanoseconds: Int

        public init(
            device: Int32,
            inode: UInt64,
            size: Int64,
            modifiedSeconds: Int,
            modifiedNanoseconds: Int
        ) {
            self.device = device
            self.inode = inode
            self.size = size
            self.modifiedSeconds = modifiedSeconds
            self.modifiedNanoseconds = modifiedNanoseconds
        }
    }

    public let executableURL: URL
    public let identity: FileIdentity?

    public init(executableURL: URL) {
        self.executableURL = executableURL
        self.identity = Self.readIdentity(at: executableURL)
    }

    public func matchesCurrentOnDisk() -> Bool {
        guard let identity else { return false }
        return Self.readIdentity(at: executableURL) == identity
    }

    public static func readIdentity(at url: URL) -> FileIdentity? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return FileIdentity(
            device: info.st_dev,
            inode: info.st_ino,
            size: info.st_size,
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec
        )
    }
}
