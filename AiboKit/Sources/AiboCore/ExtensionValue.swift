import Foundation

/// JSON value carried across the plugin protocol. The host does not interpret plugin `requestState`.
public enum ExtensionValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ExtensionValue])
    case array([ExtensionValue])
    case null

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: ExtensionValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [ExtensionValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var jsonObject: Any {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value
        case .bool(let value):
            value
        case .object(let value):
            value.mapValues(\.jsonObject)
        case .array(let value):
            value.map(\.jsonObject)
        case .null:
            NSNull()
        }
    }

    public static func from(jsonObject: Any) -> ExtensionValue {
        switch jsonObject {
        case let value as String:
            .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                .bool(value.boolValue)
            } else {
                .number(value.doubleValue)
            }
        case let value as [String: Any]:
            .object(value.mapValues(Self.from(jsonObject:)))
        case let value as [Any]:
            .array(value.map(Self.from(jsonObject:)))
        default:
            .null
        }
    }
}

extension ExtensionValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ExtensionValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([ExtensionValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum ExtensionJSON {
    public static func value(from data: Data) throws -> ExtensionValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return ExtensionValue.from(jsonObject: object)
    }

    public static func data(from value: ExtensionValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// Object at the root. Arrays and scalars are rejected.
    public static func object(from data: Data) throws -> [String: ExtensionValue] {
        let value = try value(from: data)
        guard let object = value.objectValue else {
            throw ExtensionJSONError.expectedObject
        }
        return object
    }

    public static func encodeObject(_ object: [String: ExtensionValue]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object.mapValues(\.jsonObject), options: [.sortedKeys])
    }
}

public enum ExtensionJSONError: Error, Equatable {
    case expectedObject
}
