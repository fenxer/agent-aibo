import Foundation

/// Index of extensions the app can list, install, and update.
///
/// One file, two roots. Debug can read a `catalog.json` on disk and resolve
/// `path` from the repository that contains it. Release reads the same file
/// from `raw.githubusercontent.com` and downloads each `path` from that repository.
public struct ExtensionCatalog: Sendable, Equatable {
    public var apiVersion: Int
    public var repository: String
    public var ref: String
    /// When this index was last edited, `yyyy-MM-dd`.
    public var updated: String
    public var revoked: [String]
    public var extensions: [ExtensionCatalogEntry]

    public static let supportedAPIVersion = 1

    public init(
        apiVersion: Int,
        repository: String,
        ref: String,
        updated: String,
        revoked: [String],
        extensions: [ExtensionCatalogEntry]
    ) {
        self.apiVersion = apiVersion
        self.repository = repository
        self.ref = ref
        self.updated = updated
        self.revoked = revoked
        self.extensions = extensions
    }

    public static func decode(_ data: Data) throws -> ExtensionCatalog {
        let catalog: ExtensionCatalog
        do {
            catalog = try JSONDecoder().decode(ExtensionCatalog.self, from: data)
        } catch {
            throw ExtensionCatalogError.unreadable
        }
        guard catalog.apiVersion == supportedAPIVersion else {
            throw ExtensionCatalogError.unsupportedAPIVersion(catalog.apiVersion)
        }
        return catalog
    }

    /// Entries the app may offer. Revoked ids, unknown plugin API versions, and unsafe paths are left out.
    public var listed: [ExtensionCatalogEntry] {
        let blocked = Set(revoked)
        return extensions.filter { entry in
            entry.extensionApiVersion == Self.supportedAPIVersion
                && !entry.id.isEmpty
                && !blocked.contains(entry.id)
                && ExtensionCatalogPath.error(entry.path) == nil
        }
    }

    /// `…/Extensions/catalog.json` → the repository root, two levels up.
    public static func repositoryRoot(catalogFile: URL) -> URL? {
        let file = catalogFile.standardizedFileURL
        guard file.lastPathComponent == "catalog.json" else { return nil }
        let parent = file.deletingLastPathComponent()
        guard parent.lastPathComponent == "Extensions" else { return nil }
        return parent.deletingLastPathComponent()
    }

    public func contentsAPIURL(path: String) -> URL? {
        Self.githubURL(repository: repository, ref: ref, path: path, host: "api.github.com", contents: true)
    }

    public static func rawFileURL(repository: String, ref: String, path: String) -> URL? {
        githubURL(repository: repository, ref: ref, path: path, host: "raw.githubusercontent.com", contents: false)
    }

    private static func githubURL(
        repository: String,
        ref: String,
        path: String,
        host: String,
        contents: Bool
    ) -> URL? {
        guard ExtensionCatalogPath.error(path) == nil else { return nil }
        guard let names = repositoryNames(repository), isSafeRef(ref) else { return nil }
        let encodedPath = path.split(separator: "/").map { part in
            String(part).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        }.joined(separator: "/")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        if contents {
            components.path = "/repos/\(names.owner)/\(names.name)/contents/\(encodedPath)"
            components.queryItems = [URLQueryItem(name: "ref", value: ref)]
        } else {
            let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
            components.path = "/\(names.owner)/\(names.name)/\(encodedRef)/\(encodedPath)"
        }
        return components.url
    }

    private static func repositoryNames(_ repository: String) -> (owner: String, name: String)? {
        let parts = repository.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy(isSafeRepositoryName) else { return nil }
        return (parts[0], parts[1])
    }

    private static func isSafeRepositoryName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "." || scalar == "_"
        }
    }

    private static func isSafeRef(_ ref: String) -> Bool {
        !ref.isEmpty && !ref.contains("/") && !ref.contains("..") && !ref.contains("\\")
    }
}

public enum ExtensionCatalogLocation {
    public static let repository = "fenxer/agent-aibo"
    public static let ref = "main"
    public static let catalogPath = "Extensions/catalog.json"

    public static var rawCatalogURL: URL? {
        ExtensionCatalog.rawFileURL(repository: repository, ref: ref, path: catalogPath)
    }
}

public struct ExtensionCatalogEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var slug: String?
    public var name: String
    public var summary: String
    public var author: String
    public var icon: ExtensionIcon
    public var locales: [String: ExtensionCatalogCopy]
    public var version: String
    public var extensionApiVersion: Int
    /// Raw requirement from the catalog, such as `>=1.1.0`.
    public var compatibilityAibo: String
    public var provides: [String]
    public var capabilities: [String]
    /// Repository-relative directory, such as `Extensions/dev.aibo.translate`.
    public var path: String

    public func packageDirectory(in repositoryRoot: URL) -> URL? {
        guard ExtensionCatalogPath.error(path) == nil else { return nil }
        return repositoryRoot.appendingPathComponent(path, isDirectory: true)
    }

    /// Catalog copy for the app language, then English, then the entry's own name.
    public func displayCopy(preferredLanguage: String) -> (name: String, summary: String) {
        var keys: [String] = []
        if preferredLanguage.hasPrefix("zh") {
            keys.append("zh-Hans")
        } else if preferredLanguage.hasPrefix("en") {
            keys.append("en")
        } else if !preferredLanguage.isEmpty {
            keys.append(preferredLanguage)
        }
        if !keys.contains("en") {
            keys.append("en")
        }
        for key in keys {
            if let copy = locales[key], !copy.name.isEmpty {
                return (copy.name, copy.summary)
            }
        }
        return (name, summary)
    }
}

public struct ExtensionCatalogCopy: Sendable, Equatable {
    public var name: String
    public var summary: String

    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

public enum ExtensionCatalogPath {
    public static func error(_ path: String) -> ExtensionManifestError? {
        if let error = ExtensionManifestValidator.relativePathError(path) {
            return error
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.contains(where: { $0.isEmpty || $0 == "." }) {
            return .unsafeRelativePath(path)
        }
        return nil
    }
}

public enum ExtensionCatalogError: Error, Equatable {
    case unsupportedAPIVersion(Int)
    case unreadable
}

public enum ExtensionVersion {
    /// `true` when `candidate` is a higher numeric dot-version than `installed`.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let left = components(candidate)
        let right = components(installed)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }
}

extension ExtensionCatalog: Decodable {
    enum CodingKeys: String, CodingKey {
        case apiVersion
        case repository
        case ref
        case updated
        case revoked
        case extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        repository = try container.decode(String.self, forKey: .repository)
        ref = try container.decode(String.self, forKey: .ref)
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
        revoked = try container.decodeIfPresent([String].self, forKey: .revoked) ?? []
        extensions = try container.decodeIfPresent([ExtensionCatalogEntry].self, forKey: .extensions) ?? []
    }
}

extension ExtensionCatalogEntry: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case summary = "description"
        case author
        case icon
        case locales
        case version
        case extensionApiVersion
        case compatibility
        case provides
        case capabilities
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let slug = try container.decodeIfPresent(String.self, forKey: .slug)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.slug = (slug?.isEmpty == false) ? slug : nil
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        icon = try container.decodeIfPresent(ExtensionIcon.self, forKey: .icon) ?? .fallback
        locales = try container.decodeIfPresent([String: ExtensionCatalogCopy].self, forKey: .locales) ?? [:]
        version = try container.decode(String.self, forKey: .version)
        extensionApiVersion = try container.decodeIfPresent(Int.self, forKey: .extensionApiVersion) ?? 1
        compatibilityAibo = try container.decodeIfPresent(Compatibility.self, forKey: .compatibility)?.aibo ?? ""
        provides = try container.decodeIfPresent([String].self, forKey: .provides) ?? []
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        path = try container.decode(String.self, forKey: .path)
    }

    private struct Compatibility: Decodable {
        var aibo: String
    }
}

extension ExtensionCatalogCopy: Decodable {
    enum CodingKeys: String, CodingKey {
        case name
        case summary = "description"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }
}
