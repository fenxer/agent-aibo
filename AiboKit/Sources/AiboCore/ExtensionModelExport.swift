import Foundation

/// One saved provider, minus anything the host keeps out of the plugin protocol.
public struct ExtensionProviderRecord: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var values: [String: String]

    public init(id: String, displayName: String, values: [String: String]) {
        self.id = id
        self.displayName = displayName
        self.values = values
    }
}

/// A configured model a providing plugin exposes to plugins that depend on it.
/// `fields` is the declared export. Secrets never appear here.
public struct ExtensionProvidedModel: Equatable, Sendable, Identifiable {
    public var pluginID: String
    public var providerID: String
    /// Name the user gave the provider, or the model id when they left the name blank.
    public var title: String
    public var fields: [String: String]

    public var id: String { "\(pluginID)/\(providerID)" }

    public init(pluginID: String, providerID: String, title: String, fields: [String: String]) {
        self.pluginID = pluginID
        self.providerID = providerID
        self.title = title
        self.fields = fields
    }
}

public enum ExtensionModelExport {
    /// Copies each provider's declared fields. `displayName` comes from the provider name.
    /// Keys in `sensitiveKeys` are dropped even if the manifest listed them.
    public static func models(
        pluginID: String,
        declaredFields: [String],
        providers: [ExtensionProviderRecord],
        sensitiveKeys: Set<String> = []
    ) -> [ExtensionProvidedModel] {
        providers.map { provider in
            var fields: [String: String] = [:]
            for key in declaredFields where !sensitiveKeys.contains(key) {
                if key == "displayName" {
                    fields[key] = provider.displayName
                } else {
                    fields[key] = provider.values[key] ?? ""
                }
            }
            let name = provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (provider.values["model"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = name.isEmpty ? model : name
            return ExtensionProvidedModel(
                pluginID: pluginID,
                providerID: provider.id,
                title: title,
                fields: fields
            )
        }
    }

    /// The saved id when that provider is still in the list. Otherwise the first one.
    public static func resolve(saved: String?, models: [ExtensionProvidedModel]) -> ExtensionProvidedModel? {
        let trimmed = saved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let match = models.first(where: { $0.id == trimmed }) {
            return match
        }
        return models.first
    }
}
