import Foundation

public enum HooksInstallerError: Error, Equatable, Sendable {
    case invalidJSONObject
}

/// Shared JSON object helpers for hooks.json installers.
public enum HooksConfigJSON {
    /// Throws when data exists but is not a JSON object.
    public static func parseObject(from data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw HooksInstallerError.invalidJSONObject
        }
        return dictionary
    }

    public static func encodePretty(_ config: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }
}
