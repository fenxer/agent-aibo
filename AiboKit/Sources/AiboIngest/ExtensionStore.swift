import AiboCore
import Foundation

/// Installed plugin packages under Application Support. Settings live in a separate data directory
/// so replacing the package does not wipe configuration.
public struct ExtensionPackage: Sendable, Equatable {
    public var manifest: ExtensionManifest
    public var directory: URL

    public init(manifest: ExtensionManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }

    public var entryURL: URL {
        directory.appendingPathComponent(manifest.entry)
    }
}

public struct ExtensionRegistry: Codable, Sendable, Equatable {
    public var enabledIDs: [String]
    public var invocationCounts: [String: Int]

    public init(enabledIDs: [String] = [], invocationCounts: [String: Int] = [:]) {
        self.enabledIDs = enabledIDs
        self.invocationCounts = invocationCounts
    }

    public func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    public func invocations(for id: String) -> Int {
        invocationCounts[id] ?? 0
    }
}

public enum ExtensionStoreError: Error, Equatable {
    case missingManifest
    case invalidManifest(ExtensionManifestError)
    case unsafePath(String)
    case tooLarge
    case entryMissing
    case unreadable
    case blocked(ExtensionInstallBlock)
}

public struct ExtensionStore {
    public var extensionsRoot: URL
    public var dataRoot: URL
    public var registryURL: URL
    private let fileManager: FileManager

    public static let maxBytes = 10 * 1024 * 1024
    public static let maxFiles = 500

    public init(
        extensionsRoot: URL,
        dataRoot: URL,
        registryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.extensionsRoot = extensionsRoot
        self.dataRoot = dataRoot
        self.registryURL = registryURL
        self.fileManager = fileManager
    }

    public static func live(applicationSupport: URL = AiboPaths.applicationSupportDirectory) -> ExtensionStore {
        ExtensionStore(
            extensionsRoot: applicationSupport.appendingPathComponent("extensions", isDirectory: true),
            dataRoot: applicationSupport.appendingPathComponent("extension-data", isDirectory: true),
            registryURL: applicationSupport.appendingPathComponent("extension-registry.json")
        )
    }

    public func installed() -> [ExtensionPackage] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: extensionsRoot.path) else {
            return []
        }
        return names.sorted().compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            let directory = extensionsRoot.appendingPathComponent(name, isDirectory: true)
            guard let manifest = try? readManifest(in: directory), manifest.id == name else { return nil }
            guard ExtensionManifestValidator.validate(manifest) == nil else { return nil }
            return ExtensionPackage(manifest: manifest, directory: directory)
        }
    }

    public func install(from source: URL) throws -> ExtensionManifest {
        let manifest = try readManifest(in: source)
        if let error = ExtensionManifestValidator.validate(manifest) {
            throw ExtensionStoreError.invalidManifest(error)
        }
        if let block = ExtensionInstallPolicy.block(
            installing: manifest,
            alongside: installed().map(\.manifest)
        ) {
            throw ExtensionStoreError.blocked(block)
        }
        let files = try collectFiles(in: source)
        let stagingParent = extensionsRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let staging = stagingParent.appendingPathComponent(manifest.id, isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            for file in files {
                let destination = staging.appendingPathComponent(file.relativePath)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: file.source, to: destination)
            }
            let entry = staging.appendingPathComponent(manifest.entry)
            guard fileManager.fileExists(atPath: entry.path), !isSymlink(entry) else {
                throw ExtensionStoreError.entryMissing
            }
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
            let root = staging.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(root + "/") || resolved == root else {
                throw ExtensionStoreError.unsafePath(manifest.entry)
            }
            let replacing = fileManager.fileExists(
                atPath: extensionsRoot.appendingPathComponent(manifest.id, isDirectory: true).path
            )
            try replace(id: manifest.id, with: staging)
            if !replacing {
                var registry = loadRegistry()
                if !registry.enabledIDs.contains(manifest.id) {
                    registry.enabledIDs.append(manifest.id)
                }
                try saveRegistry(registry)
            }
            try? fileManager.removeItem(at: stagingParent)
            return manifest
        } catch {
            try? fileManager.removeItem(at: stagingParent)
            throw error
        }
    }

    public func uninstall(id: String) throws {
        let package = extensionsRoot.appendingPathComponent(id, isDirectory: true)
        let data = dataRoot.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: package.path) {
            try fileManager.removeItem(at: package)
        }
        if fileManager.fileExists(atPath: data.path) {
            try fileManager.removeItem(at: data)
        }
        var registry = loadRegistry()
        registry.enabledIDs.removeAll { $0 == id }
        registry.invocationCounts.removeValue(forKey: id)
        try saveRegistry(registry)
    }

    public func loadRegistry() -> ExtensionRegistry {
        guard let data = try? Data(contentsOf: registryURL),
              let registry = try? JSONDecoder().decode(ExtensionRegistry.self, from: data)
        else {
            return ExtensionRegistry()
        }
        return registry
    }

    public func saveRegistry(_ registry: ExtensionRegistry) throws {
        try writeAtomic(try JSONEncoder().encode(registry), to: registryURL)
    }

    public func loadSettings(id: String) -> [String: ExtensionValue] {
        let url = settingsURL(id: id)
        guard let data = try? Data(contentsOf: url),
              let object = try? ExtensionJSON.object(from: data)
        else {
            return [:]
        }
        return object
    }

    public func saveSettings(id: String, values: [String: ExtensionValue]) throws {
        try writeAtomic(try ExtensionJSON.encodeObject(values), to: settingsURL(id: id))
    }

    public func loadLocaleStrings(in directory: URL, localization: ExtensionLocalization?) -> [String: String] {
        guard let localization else { return [:] }
        let locales = preferredLocales(defaultLocale: localization.defaultLocale)
        for locale in locales {
            let relative = localization.resources.replacingOccurrences(of: "${locale}", with: locale)
            guard ExtensionManifestValidator.relativePathError(relative) == nil else { continue }
            let url = directory.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            var strings: [String: String] = [:]
            for (key, value) in object {
                if let text = value as? String {
                    strings[key] = text
                }
            }
            if !strings.isEmpty { return strings }
        }
        return [:]
    }

    public func sensitiveKeys(in schema: ExtensionObjectSchema?) -> [String] {
        guard let schema else { return [] }
        return schema.properties.compactMap { key, field in
            field.sensitive ? key : nil
        }
    }

    private func settingsURL(id: String) -> URL {
        dataRoot
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func readManifest(in directory: URL) throws -> ExtensionManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            throw ExtensionStoreError.missingManifest
        }
        do {
            return try JSONDecoder().decode(ExtensionManifest.self, from: data)
        } catch let error as ExtensionManifestError {
            throw ExtensionStoreError.invalidManifest(error)
        } catch {
            throw ExtensionStoreError.unreadable
        }
    }

    private struct CollectedFile {
        var relativePath: String
        var source: URL
    }

    private func collectFiles(in source: URL) throws -> [CollectedFile] {
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ExtensionStoreError.unreadable
        }
        var files: [CollectedFile] = []
        var total = 0
        for case let url as URL in enumerator {
            if isSymlink(url) {
                throw ExtensionStoreError.unsafePath(url.lastPathComponent)
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let root = source.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(root + "/") else {
                throw ExtensionStoreError.unsafePath(url.lastPathComponent)
            }
            let relative = String(filePath.dropFirst(root.count + 1))
            if ExtensionManifestValidator.relativePathError(relative) != nil {
                throw ExtensionStoreError.unsafePath(relative)
            }
            total += values.fileSize ?? 0
            if total > Self.maxBytes || files.count >= Self.maxFiles {
                throw ExtensionStoreError.tooLarge
            }
            files.append(CollectedFile(relativePath: relative, source: url))
        }
        return files
    }

    private func replace(id: String, with staging: URL) throws {
        try fileManager.createDirectory(at: extensionsRoot, withIntermediateDirectories: true)
        let final = extensionsRoot.appendingPathComponent(id, isDirectory: true)
        let backup = extensionsRoot.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        let hadPrevious = fileManager.fileExists(atPath: final.path)
        if hadPrevious {
            try fileManager.moveItem(at: final, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: final)
            if hadPrevious {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if hadPrevious, !fileManager.fileExists(atPath: final.path) {
                try? fileManager.moveItem(at: backup, to: final)
            }
            throw error
        }
    }

    private func writeAtomic(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func preferredLocales(defaultLocale: String) -> [String] {
        var locales: [String] = []
        let preferred = Locale.preferredLanguages.first ?? defaultLocale
        if preferred.hasPrefix("zh") {
            locales.append("zh-Hans")
        } else if preferred.hasPrefix("en") {
            locales.append("en")
        } else {
            locales.append(preferred)
        }
        if !locales.contains(defaultLocale) {
            locales.append(defaultLocale)
        }
        if !locales.contains("en") {
            locales.append("en")
        }
        return locales
    }
}
