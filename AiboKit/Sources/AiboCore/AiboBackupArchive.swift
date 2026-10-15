import Foundation

public enum AiboBackupArchive {
    public static let formatIdentifier = "aibo-backup"
    public static let formatVersion = 1
    public static let fileExtension = "aiboarchive"

    /// `aibo-backup-261014.aiboarchive` for 14 Oct 2026, in `calendar`'s time zone.
    public static func suggestedFileName(on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = (parts.year ?? 0) % 100
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "aibo-backup-%02d%02d%02d.\(fileExtension)", year, month, day)
    }
    public static let manifestFileName = "manifest.json"
    public static let settingsFileName = "settings.json"
    public static let playtimeFileName = "playtime.json"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public struct Document: Equatable, Sendable {
        public var manifest: AiboBackupManifest
        public var settings: AiboBackupSettings
        public var playtime: AiboBackupPlaytimeFile
        public var aibosDirectory: URL
    }

    /// Previous library tree, kept until `commit`. `restore` puts it back and removes the imported tree.
    public struct LibraryReplacement: Sendable {
        private var previous: URL?
        public let destination: URL

        fileprivate init(previous: URL?, destination: URL) {
            self.previous = previous
            self.destination = destination
        }

        public mutating func commit(fileManager: FileManager = .default) {
            guard let previous else { return }
            try? fileManager.removeItem(at: previous)
            self.previous = nil
        }

        public mutating func restore(fileManager: FileManager = .default) throws {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            if let previous {
                try fileManager.moveItem(at: previous, to: destination)
                self.previous = nil
            }
        }
    }

    public static func write(
        settings: AiboBackupSettings,
        playtime: AiboBackupPlaytimeFile,
        aibosSource: URL,
        appVersion: String,
        exportedAt: Date = Date(),
        to archiveURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard settings.hasCoherentValues() else { throw AiboBackupError.invalidContents }
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("aibo-backup-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let manifest = AiboBackupManifest(
            format: formatIdentifier,
            formatVersion: formatVersion,
            exportedAt: exportedAt,
            appVersion: appVersion
        )
        try encoder.encode(manifest).write(
            to: staging.appendingPathComponent(manifestFileName),
            options: .atomic
        )
        try encoder.encode(settings).write(
            to: staging.appendingPathComponent(settingsFileName),
            options: .atomic
        )
        try encoder.encode(playtime).write(
            to: staging.appendingPathComponent(playtimeFileName),
            options: .atomic
        )

        let packedAibos = staging.appendingPathComponent(AiboPaths.aibosDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: aibosSource.path) {
            try copyTree(from: aibosSource, to: packedAibos, fileManager: fileManager)
            try validateAibos(packedAibos, fileManager: fileManager)
        } else {
            try fileManager.createDirectory(at: packedAibos, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try runDitto(
            arguments: ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", staging.path, archiveURL.path]
        )
    }

    /// Extracts into `root`, which the caller owns and deletes.
    public static func read(
        archive: URL,
        into root: URL,
        fileManager: FileManager = .default
    ) throws -> Document {
        try assertZipEntriesStayInside(archive)
        try? fileManager.removeItem(at: root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try runDitto(arguments: ["-x", "-k", "--", archive.path, root.path])
        try assertExtractedTreeStaysInside(root, fileManager: fileManager)

        let manifest = try decode(
            AiboBackupManifest.self,
            from: root.appendingPathComponent(manifestFileName),
            fileManager: fileManager
        )
        guard manifest.format == formatIdentifier else { throw AiboBackupError.invalidContents }
        guard manifest.formatVersion == formatVersion else { throw AiboBackupError.unsupportedFormat }

        let settings = try decode(
            AiboBackupSettings.self,
            from: root.appendingPathComponent(settingsFileName),
            fileManager: fileManager
        )
        guard settings.hasCoherentValues() else { throw AiboBackupError.invalidContents }
        let playtime = try decode(
            AiboBackupPlaytimeFile.self,
            from: root.appendingPathComponent(playtimeFileName),
            fileManager: fileManager
        )
        let aibos = root.appendingPathComponent(AiboPaths.aibosDirectoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: aibos.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AiboBackupError.invalidContents
        }
        try validateAibos(aibos, fileManager: fileManager)
        return Document(
            manifest: manifest,
            settings: settings,
            playtime: playtime,
            aibosDirectory: aibos
        )
    }

    /// Moves `source` onto `destination`. `source` is consumed.
    public static func replaceLibrary(
        at destination: URL,
        with source: URL,
        fileManager: FileManager = .default
    ) throws -> LibraryReplacement {
        try validateAibos(source, fileManager: fileManager)
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".aibos-incoming-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.moveItem(at: source, to: staging)
        } catch {
            throw AiboBackupError.ioFailed
        }

        var previous: URL?
        if fileManager.fileExists(atPath: destination.path) {
            let backup = parent.appendingPathComponent(".aibos-previous-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.moveItem(at: destination, to: backup)
                previous = backup
            } catch {
                try? fileManager.removeItem(at: staging)
                throw AiboBackupError.ioFailed
            }
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if let previous {
                try? fileManager.moveItem(at: previous, to: destination)
            }
            try? fileManager.removeItem(at: staging)
            throw AiboBackupError.ioFailed
        }
        return LibraryReplacement(previous: previous, destination: destination)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        fileManager: FileManager
    ) throws -> T {
        if isSymlink(url) { throw AiboBackupError.unsafePath }
        guard let data = try? Data(contentsOf: url) else { throw AiboBackupError.invalidContents }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AiboBackupError.invalidContents
        }
    }

    private static func validateAibos(_ directory: URL, fileManager: FileManager) throws {
        if isSymlink(directory) { throw AiboBackupError.unsafePath }
        try rejectSymlinks(under: directory, fileManager: fileManager)
        let library = directory.appendingPathComponent(AiboPaths.libraryFileName)
        guard fileManager.fileExists(atPath: library.path) else { return }
        if isSymlink(library) { throw AiboBackupError.unsafePath }
        guard let data = try? Data(contentsOf: library) else { throw AiboBackupError.invalidContents }
        do {
            _ = try AiboLibraryCodec.decode(data)
        } catch {
            throw AiboBackupError.invalidContents
        }
    }

    private static func copyTree(from source: URL, to destination: URL, fileManager: FileManager) throws {
        if isSymlink(source) { throw AiboBackupError.unsafePath }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AiboBackupError.invalidContents
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try copyContents(of: source, to: destination, fileManager: fileManager)
    }

    private static func copyContents(of source: URL, to destination: URL, fileManager: FileManager) throws {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: source.path)
        } catch {
            throw AiboBackupError.unreadable
        }
        for name in names where !name.hasPrefix(".") {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if isSymlink(from) { throw AiboBackupError.unsafePath }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: from.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
                try copyContents(of: from, to: to, fileManager: fileManager)
            } else {
                do {
                    try fileManager.copyItem(at: from, to: to)
                } catch {
                    throw AiboBackupError.ioFailed
                }
            }
        }
    }

    private static func rejectSymlinks(under root: URL, fileManager: FileManager) throws {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else {
            throw AiboBackupError.unreadable
        }
        for name in names where !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name)
            if isSymlink(url) { throw AiboBackupError.unsafePath }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                try rejectSymlinks(under: url, fileManager: fileManager)
            }
        }
    }

    private static func assertZipEntriesStayInside(_ archive: URL) throws {
        let listing = try runAndCapture(["/usr/bin/unzip", "-Z", "-1", "--", archive.path])
        for line in listing.split(whereSeparator: \.isNewline) {
            let name = String(line)
            if name.isEmpty { continue }
            if name.hasPrefix("/") || name.hasPrefix("\\") { throw AiboBackupError.unsafePath }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            if parts.contains("..") || parts.contains(".") { throw AiboBackupError.unsafePath }
        }
    }

    private static func assertExtractedTreeStaysInside(_ root: URL, fileManager: FileManager) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        try rejectSymlinks(under: root, fileManager: fileManager)
        guard let enumerator = fileManager.enumerator(atPath: root.path) else {
            throw AiboBackupError.unreadable
        }
        while let relative = enumerator.nextObject() as? String {
            if relative.split(separator: "/").contains("..") { throw AiboBackupError.unsafePath }
            let url = root.appendingPathComponent(relative).standardizedFileURL
            let path = url.path
            guard path == rootPath || path.hasPrefix(rootPath + "/") else {
                throw AiboBackupError.unsafePath
            }
        }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func runDitto(arguments: [String]) throws {
        do {
            let status = try run(["/usr/bin/ditto"] + arguments)
            guard status == 0 else { throw AiboBackupError.ioFailed }
        } catch let error as AiboBackupError {
            throw error
        } catch {
            throw AiboBackupError.ioFailed
        }
    }

    @discardableResult
    private static func run(_ command: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func runAndCapture(_ command: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AiboBackupError.unreadable }
        return String(decoding: data, as: UTF8.self)
    }
}
