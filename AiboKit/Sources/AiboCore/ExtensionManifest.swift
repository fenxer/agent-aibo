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
    /// Author-declared tile. Missing `icon` uses the default symbol and appearance colors.
    public var icon: ExtensionIcon = .fallback

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
    /// Plates that hold more than one field. Each entry is a section (`{ "fields": [...] }`).
    /// A field that belongs to no section is its own plate, placed where `order` puts it.
    public var sections: [ExtensionFieldSection]

    public var orderedKeys: [String] {
        let known = order.filter { properties[$0] != nil }
        let rest = properties.keys.filter { !known.contains($0) }.sorted()
        return known + rest
    }

    /// Field keys grouped into plates. A section is emitted at its first member.
    public func fieldGroups() -> [[String]] {
        var sectionIndex: [String: Int] = [:]
        for (index, section) in sections.enumerated() {
            for key in section.fields where properties[key] != nil {
                if sectionIndex[key] == nil {
                    sectionIndex[key] = index
                }
            }
        }
        var emitted: Set<Int> = []
        var groups: [[String]] = []
        for key in orderedKeys {
            guard let index = sectionIndex[key] else {
                groups.append([key])
                continue
            }
            if emitted.contains(index) { continue }
            emitted.insert(index)
            let keys = sections[index].fields.filter { properties[$0] != nil && sectionIndex[$0] == index }
            if !keys.isEmpty {
                groups.append(keys)
            }
        }
        return groups
    }

    public init(
        type: String = "object",
        order: [String] = [],
        properties: [String: ExtensionFieldSchema],
        required: [String] = [],
        sections: [ExtensionFieldSection] = []
    ) {
        self.type = type
        self.order = order
        self.properties = properties
        self.required = required
        self.sections = sections
    }
}

/// One prompt plate that holds several fields. JSON: `{ "fields": ["tone", "formal"] }`.
public struct ExtensionFieldSection: Codable, Sendable, Equatable {
    public var fields: [String]

    public init(fields: [String]) {
        self.fields = fields
    }
}

public struct ExtensionFieldSchema: Sendable, Equatable {
    public var type: String
    /// Prompt widget. `line`, `text`, `menu`, `radio`, `switch`, or `image`.
    /// Omitted: a field with `oneOf` is a menu, `boolean` is a switch, anything else is multiline text.
    public var control: String?
    public var title: String?
    public var summary: String?
    public var defaultValue: ExtensionValue?
    public var sensitive: Bool
    public var oneOf: [ExtensionChoice]
    public var minLength: Int?
    public var maxLength: Int?

    public init(
        type: String,
        control: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        defaultValue: ExtensionValue? = nil,
        sensitive: Bool = false,
        oneOf: [ExtensionChoice] = [],
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.type = type
        self.control = control
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
    case invalidIcon(String)
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
        case icon
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
        icon = try container.decodeIfPresent(ExtensionIcon.self, forKey: .icon) ?? .fallback
    }
}

/// Plugin tile. Authors either name a 1:1 image in the plugin folder, or a
/// background plus an SF Symbol. A single color is used for both appearances
/// when only one is set. Symbol ink uses the declared color, or black/white
/// from the background contrast when it is omitted.
public struct ExtensionIcon: Sendable, Equatable {
    public static let defaultSymbol = "square.text.square.fill"
    public static let fallback = ExtensionIcon()

    /// Relative path of a 1:1 image inside the plugin directory.
    public var image: String?
    public var symbol: String
    /// Hex `#RGB` or `#RRGGBB`. Nil means the host default for that appearance.
    public var lightBackground: String?
    public var darkBackground: String?
    /// Hex for the symbol. Nil means black or white from the background contrast.
    public var lightSymbol: String?
    public var darkSymbol: String?

    public init(
        image: String? = nil,
        symbol: String = defaultSymbol,
        lightBackground: String? = nil,
        darkBackground: String? = nil,
        lightSymbol: String? = nil,
        darkSymbol: String? = nil
    ) {
        self.image = image
        self.symbol = symbol
        self.lightBackground = lightBackground
        self.darkBackground = darkBackground
        self.lightSymbol = lightSymbol
        self.darkSymbol = darkSymbol
    }

    /// One declared color fills the appearance that was left out.
    public func backgroundHex(dark: Bool) -> String? {
        appearanceHex(light: lightBackground, night: darkBackground, dark: dark)
    }

    public func symbolHex(dark: Bool) -> String? {
        appearanceHex(light: lightSymbol, night: darkSymbol, dark: dark)
    }

    private func appearanceHex(light: String?, night: String?, dark: Bool) -> String? {
        let day = nonempty(light)
        let evening = nonempty(night)
        if dark { return evening ?? day }
        return day ?? evening
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

extension ExtensionIcon: Codable {
    private enum CodingKeys: String, CodingKey {
        case image
        case symbol
        case background
        case symbolColor
    }

    private enum AppearanceKey: String, CodingKey {
        case light
        case dark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let image = try container.decodeIfPresent(String.self, forKey: .image), !image.isEmpty {
            self.image = image
        } else {
            self.image = nil
        }
        if let symbol = try container.decodeIfPresent(String.self, forKey: .symbol), !symbol.isEmpty {
            self.symbol = symbol
        } else {
            self.symbol = Self.defaultSymbol
        }
        if container.contains(.background) {
            switch try container.decode(ColorValue.self, forKey: .background) {
            case .hex(let hex):
                lightBackground = hex
                darkBackground = hex
            case .pair(let light, let dark):
                lightBackground = light
                darkBackground = dark
            }
        } else {
            lightBackground = nil
            darkBackground = nil
        }
        if container.contains(.symbolColor) {
            switch try container.decode(ColorValue.self, forKey: .symbolColor) {
            case .hex(let hex):
                lightSymbol = hex
                darkSymbol = hex
            case .pair(let light, let dark):
                lightSymbol = light
                darkSymbol = dark
            }
        } else {
            lightSymbol = nil
            darkSymbol = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(image, forKey: .image)
        if symbol != Self.defaultSymbol {
            try container.encode(symbol, forKey: .symbol)
        }
        if let light = lightBackground, let dark = darkBackground, light == dark {
            try container.encode(light, forKey: .background)
        } else if lightBackground != nil || darkBackground != nil {
            var pair = container.nestedContainer(keyedBy: AppearanceKey.self, forKey: .background)
            try pair.encodeIfPresent(lightBackground, forKey: .light)
            try pair.encodeIfPresent(darkBackground, forKey: .dark)
        }
        if let light = lightSymbol, let dark = darkSymbol, light == dark {
            try container.encode(light, forKey: .symbolColor)
        } else if lightSymbol != nil || darkSymbol != nil {
            var pair = container.nestedContainer(keyedBy: AppearanceKey.self, forKey: .symbolColor)
            try pair.encodeIfPresent(lightSymbol, forKey: .light)
            try pair.encodeIfPresent(darkSymbol, forKey: .dark)
        }
    }

    private enum ColorValue: Decodable {
        case hex(String)
        case pair(light: String?, dark: String?)

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: AppearanceKey.self),
               !container.allKeys.isEmpty {
                self = .pair(
                    light: try container.decodeIfPresent(String.self, forKey: .light),
                    dark: try container.decodeIfPresent(String.self, forKey: .dark)
                )
                return
            }
            let single = try decoder.singleValueContainer()
            self = .hex(try single.decode(String.self))
        }
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
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "object"
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        properties = try container.decodeIfPresent([String: ExtensionFieldSchema].self, forKey: .properties) ?? [:]
        required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
        sections = try container.decodeIfPresent([ExtensionFieldSection].self, forKey: .sections) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(order, forKey: .order)
        try container.encode(properties, forKey: .properties)
        try container.encode(required, forKey: .required)
        if !sections.isEmpty {
            try container.encode(sections, forKey: .sections)
        }
    }
}

extension ExtensionFieldSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case control
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
        control = try container.decodeIfPresent(String.self, forKey: .control)
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
        try container.encodeIfPresent(control, forKey: .control)
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
        if let settings = manifest.settings, let error = schemaError(settings) {
            return error
        }
        if let prompt = manifest.prompt, let error = schemaError(prompt) {
            return error
        }
        if let error = iconError(manifest.icon) {
            return error
        }
        return nil
    }

    private static func iconError(_ icon: ExtensionIcon) -> ExtensionManifestError? {
        if let image = icon.image {
            if let error = relativePathError(image) { return error }
        }
        if icon.symbol.isEmpty { return .missingField("icon.symbol") }
        if let light = icon.lightBackground, let error = colorError(light) { return error }
        if let dark = icon.darkBackground, let error = colorError(dark) { return error }
        if let light = icon.lightSymbol, let error = colorError(light) { return error }
        if let dark = icon.darkSymbol, let error = colorError(dark) { return error }
        return nil
    }

    private static func colorError(_ hex: String) -> ExtensionManifestError? {
        let pattern = #"^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$"#
        if hex.range(of: pattern, options: .regularExpression) == nil {
            return .invalidIcon(hex)
        }
        return nil
    }

    private static let promptControls: Set<String> = ["line", "text", "menu", "radio", "switch", "image"]

    private static func schemaError(_ schema: ExtensionObjectSchema) -> ExtensionManifestError? {
        if schema.type != "object" { return .invalidSchema }
        for field in schema.properties.values {
            if let control = field.control {
                if !Self.promptControls.contains(control) { return .invalidSchema }
                if (control == "menu" || control == "radio"), field.oneOf.isEmpty {
                    return .invalidSchema
                }
            }
        }
        var seen: Set<String> = []
        for section in schema.sections {
            if section.fields.isEmpty { return .invalidSchema }
            for key in section.fields {
                if schema.properties[key] == nil || !seen.insert(key).inserted {
                    return .invalidSchema
                }
            }
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
