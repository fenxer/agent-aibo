import Foundation

/// Plugin manifest (`manifest.json`). Unknown JSON fields are ignored.
///
/// Prototype fields beyond the v1 draft, all optional:
/// `provides` (a capability other plugins can request, currently `llm`),
/// `io` (labels for the plugin list), and `prompt` (the manual-run input form).
public struct ExtensionManifest: Sendable, Equatable {
    public var apiVersion: Int
    public var id: String
    public var name: String
    public var summary: String
    public var version: String
    public var author: String
    public var runtime: String
    public var entry: String
    public var triggers: [ExtensionTrigger]
    public var accepts: [String]
    public var capabilities: [String]
    public var provides: [String]
    public var network: ExtensionNetwork
    public var settings: ExtensionObjectSchema?
    public var prompt: ExtensionObjectSchema?
    public var rewrite: Bool
    public var localization: ExtensionLocalization?
    public var io: ExtensionIO

    public var hasManualTrigger: Bool {
        triggers.contains { $0.kind == "manual" }
    }

    public var providesModel: Bool {
        provides.contains("llm")
    }

    public var usesModel: Bool {
        capabilities.contains("llm") || rewrite
    }
}

public struct ExtensionTrigger: Codable, Sendable, Equatable {
    public var kind: String

    public init(kind: String) {
        self.kind = kind
    }
}

public struct ExtensionNetwork: Sendable, Equatable {
    public var hosts: [String]

    public init(hosts: [String]) {
        self.hosts = hosts
    }
}

public struct ExtensionLocalization: Codable, Sendable, Equatable {
    public var resources: String
    public var defaultLocale: String

    public init(resources: String, defaultLocale: String) {
        self.resources = resources
        self.defaultLocale = defaultLocale
    }
}

public struct ExtensionIO: Codable, Sendable, Equatable {
    public var inputs: [ExtensionIOItem]
    public var outputs: [ExtensionIOItem]

    public init(inputs: [ExtensionIOItem], outputs: [ExtensionIOItem]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct ExtensionIOItem: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String

    public init(id: String, kind: String) {
        self.id = id
        self.kind = kind
    }
}

public struct ExtensionObjectSchema: Sendable, Equatable {
    public var type: String
    public var order: [String]
    public var properties: [String: ExtensionFieldSchema]
    public var required: [String]

    public var orderedKeys: [String] {
        let known = order.filter { properties[$0] != nil }
        let rest = properties.keys.filter { !known.contains($0) }.sorted()
        return known + rest
    }

    public init(
        type: String = "object",
        order: [String] = [],
        properties: [String: ExtensionFieldSchema],
        required: [String] = []
    ) {
        self.type = type
        self.order = order
        self.properties = properties
        self.required = required
    }
}

public struct ExtensionFieldSchema: Sendable, Equatable {
    public var type: String
    public var title: String?
    public var summary: String?
    public var defaultValue: ExtensionValue?
    public var sensitive: Bool
    public var oneOf: [ExtensionChoice]
    public var minLength: Int?
    public var maxLength: Int?

    public init(
        type: String,
        title: String? = nil,
        summary: String? = nil,
        defaultValue: ExtensionValue? = nil,
        sensitive: Bool = false,
        oneOf: [ExtensionChoice] = [],
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.type = type
        self.title = title
        self.summary = summary
        self.defaultValue = defaultValue
        self.sensitive = sensitive
        self.oneOf = oneOf
        self.minLength = minLength
        self.maxLength = maxLength
    }
}

public struct ExtensionChoice: Codable, Sendable, Equatable {
    public var value: String
    public var title: String

    public init(value: String, title: String) {
        self.value = value
        self.title = title
    }
}

public enum ExtensionManifestError: Error, Equatable {
    case unsupportedAPIVersion(Int)
    case invalidIdentifier(String)
    case missingField(String)
    case unsupportedRuntime(String)
    case unsafeRelativePath(String)
    case invalidSchema
}

extension ExtensionManifest: Codable {
    enum CodingKeys: String, CodingKey {
        case apiVersion
        case id
        case name
        case summary = "description"
        case version
        case author
        case runtime
        case entry
        case triggers
        case accepts
        case capabilities
        case provides
        case network
        case settings
        case prompt
        case rewrite
        case localization
        case io
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        version = try container.decode(String.self, forKey: .version)
        author = try container.decode(String.self, forKey: .author)
        runtime = try container.decode(String.self, forKey: .runtime)
        entry = try container.decode(String.self, forKey: .entry)
        triggers = try container.decodeIfPresent([ExtensionTrigger].self, forKey: .triggers) ?? []
        accepts = try container.decodeIfPresent([String].self, forKey: .accepts) ?? []
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        provides = try container.decodeIfPresent([String].self, forKey: .provides) ?? []
        network = try container.decodeIfPresent(ExtensionNetwork.self, forKey: .network)
            ?? ExtensionNetwork(hosts: [])
        settings = try container.decodeIfPresent(ExtensionObjectSchema.self, forKey: .settings)
        prompt = try container.decodeIfPresent(ExtensionObjectSchema.self, forKey: .prompt)
        rewrite = try container.decodeIfPresent(Bool.self, forKey: .rewrite) ?? false
        localization = try container.decodeIfPresent(ExtensionLocalization.self, forKey: .localization)
        io = try container.decodeIfPresent(ExtensionIO.self, forKey: .io)
            ?? ExtensionIO(inputs: [], outputs: [])
    }
}

extension ExtensionNetwork: Codable {
    enum CodingKeys: String, CodingKey {
        case hosts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try container.decodeIfPresent([String].self, forKey: .hosts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hosts, forKey: .hosts)
    }
}

extension ExtensionObjectSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case order
        case properties
        case required
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "object"
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        properties = try container.decodeIfPresent([String: ExtensionFieldSchema].self, forKey: .properties) ?? [:]
        required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(order, forKey: .order)
        try container.encode(properties, forKey: .properties)
        try container.encode(required, forKey: .required)
    }
}

extension ExtensionFieldSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case title
        case summary = "description"
        case defaultValue = "default"
        case sensitive
        case oneOf
        case minLength
        case maxLength
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        defaultValue = try container.decodeIfPresent(ExtensionValue.self, forKey: .defaultValue)
        sensitive = try container.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        let choices = try container.decodeIfPresent([RawChoice].self, forKey: .oneOf) ?? []
        oneOf = choices.map { ExtensionChoice(value: $0.value, title: $0.title) }
        minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
        maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        if sensitive {
            try container.encode(true, forKey: .sensitive)
        }
        if !oneOf.isEmpty {
            try container.encode(oneOf.map { RawChoice(value: $0.value, title: $0.title) }, forKey: .oneOf)
        }
        try container.encodeIfPresent(minLength, forKey: .minLength)
        try container.encodeIfPresent(maxLength, forKey: .maxLength)
    }

    private struct RawChoice: Codable {
        var value: String
        var title: String

        enum CodingKeys: String, CodingKey {
            case value = "const"
            case title
        }
    }
}

public enum ExtensionManifestValidator {
    public static func validate(_ manifest: ExtensionManifest) -> ExtensionManifestError? {
        if manifest.apiVersion != 1 {
            return .unsupportedAPIVersion(manifest.apiVersion)
        }
        if !isReverseDNS(manifest.id) {
            return .invalidIdentifier(manifest.id)
        }
        if manifest.name.isEmpty { return .missingField("name") }
        if manifest.summary.isEmpty { return .missingField("description") }
        if manifest.version.isEmpty { return .missingField("version") }
        if manifest.author.isEmpty { return .missingField("author") }
        if manifest.runtime != "js" {
            return .unsupportedRuntime(manifest.runtime)
        }
        if let error = relativePathError(manifest.entry) {
            return error
        }
        if let localization = manifest.localization {
            if !localization.resources.contains("${locale}") {
                return .unsafeRelativePath(localization.resources)
            }
            let sample = localization.resources.replacingOccurrences(of: "${locale}", with: "en")
            if let error = relativePathError(sample) {
                return error
            }
        }
        if let settings = manifest.settings, settings.type != "object" {
            return .invalidSchema
        }
        if let prompt = manifest.prompt, prompt.type != "object" {
            return .invalidSchema
        }
        return nil
    }

    public static func isReverseDNS(_ id: String) -> Bool {
        let pattern = #"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    /// Relative path that stays inside the plugin directory after resolution.
    public static func relativePathError(_ path: String) -> ExtensionManifestError? {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") || path.contains("\0") {
            return .unsafeRelativePath(path)
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.contains("..") {
            return .unsafeRelativePath(path)
        }
        return nil
    }
}
