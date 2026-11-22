import Darwin
import Foundation

/// One round of `aibo/run`. Plugins stay stateless; cross-round context is `requestState`.
public enum ExtensionRoundResult: Sendable, Equatable {
    case complete(ExtensionCompletion)
    case inputRequired(requests: [String: ExtensionInputRequest], requestState: String)
}

public struct ExtensionCompletion: Sendable, Equatable {
    public var content: [ExtensionBubbleContent]
    public var output: [String: ExtensionValue]

    public init(content: [ExtensionBubbleContent], output: [String: ExtensionValue] = [:]) {
        self.content = content
        self.output = output
    }
}

/// How the host should draw a finished bubble.
///
/// The plugin picks this. A summary by itself is not enough: the same sentence
/// can be a real result or a failure, and the user cannot tell which.
/// The host owns the badge (“Running”, “Completed”, “Warning”, “Failed”).
/// `status` is kept so older payloads still decode; it is not shown.
public enum ExtensionBubbleOutcome: String, Sendable, Equatable {
    case success
    case failure
    case warning
}

public struct ExtensionBubbleContent: Sendable, Equatable {
    public var outcome: ExtensionBubbleOutcome
    public var status: String?
    public var summary: String
    public var actions: [ExtensionBubbleAction]

    public init(
        outcome: ExtensionBubbleOutcome = .success,
        status: String? = nil,
        summary: String,
        actions: [ExtensionBubbleAction] = []
    ) {
        self.outcome = outcome
        self.status = status
        self.summary = summary
        self.actions = actions
    }
}

public struct ExtensionBubbleAction: Sendable, Equatable {
    public var title: String
    public var copyText: String?
    public var open: String?

    public init(title: String, copyText: String? = nil, open: String? = nil) {
        self.title = title
        self.copyText = copyText
        self.open = open
    }
}

public struct ExtensionInputRequest: Sendable, Equatable {
    public var method: String
    public var params: [String: ExtensionValue]

    public init(method: String, params: [String: ExtensionValue]) {
        self.method = method
        self.params = params
    }
}

public enum ExtensionRoundDecodingError: Error, Equatable {
    case expectedObject
    case unknownResultType
    case missingSummary
    case requestStateTooLarge
}

public enum ExtensionRoundCodec {
    public static let requestStateLimit = 16 * 1024

    public static func decode(_ data: Data) throws -> ExtensionRoundResult {
        let root = try ExtensionJSON.object(from: data)
        let resultType = root["resultType"]?.stringValue ?? ""
        switch resultType {
        case "complete":
            return .complete(try completion(from: root))
        case "input_required":
            let state = root["requestState"]?.stringValue ?? ""
            if state.utf8.count > requestStateLimit {
                throw ExtensionRoundDecodingError.requestStateTooLarge
            }
            let requests = try inputRequests(from: root["inputRequests"])
            return .inputRequired(requests: requests, requestState: state)
        default:
            throw ExtensionRoundDecodingError.unknownResultType
        }
    }

    private static func completion(from root: [String: ExtensionValue]) throws -> ExtensionCompletion {
        var bubbles: [ExtensionBubbleContent] = []
        if case .array(let content) = root["content"] {
            for item in content {
                guard let object = item.objectValue else { continue }
                guard object["type"]?.stringValue == "bubble" else { continue }
                guard let summary = object["summary"]?.stringValue, !summary.isEmpty else {
                    throw ExtensionRoundDecodingError.missingSummary
                }
                bubbles.append(
                    ExtensionBubbleContent(
                        outcome: outcome(from: object["outcome"]?.stringValue),
                        status: object["status"]?.stringValue,
                        summary: summary,
                        actions: actions(from: object["actions"])
                    )
                )
            }
        }
        let output = root["output"]?.objectValue ?? [:]
        return ExtensionCompletion(content: bubbles, output: output)
    }

    /// Missing `outcome` stays a normal result so older plugins keep working.
    /// An unknown token is a failure: a typo must not look like real output.
    private static func outcome(from raw: String?) -> ExtensionBubbleOutcome {
        guard let raw, !raw.isEmpty else { return .success }
        return ExtensionBubbleOutcome(rawValue: raw) ?? .failure
    }

    private static func actions(from value: ExtensionValue?) -> [ExtensionBubbleAction] {
        guard case .array(let items) = value else { return [] }
        return items.prefix(3).compactMap { item in
            guard let object = item.objectValue, let title = object["title"]?.stringValue else { return nil }
            return ExtensionBubbleAction(
                title: title,
                copyText: object["copy"]?.stringValue,
                open: object["open"]?.stringValue
            )
        }
    }

    private static let maxInputRequestsPerRound = 16

    private static func inputRequests(from value: ExtensionValue?) throws -> [String: ExtensionInputRequest] {
        guard let object = value?.objectValue else { return [:] }
        var requests: [String: ExtensionInputRequest] = [:]
        for (key, raw) in object {
            guard requests.count < maxInputRequestsPerRound else { break }
            guard let body = raw.objectValue, let method = body["method"]?.stringValue else { continue }
            requests[key] = ExtensionInputRequest(
                method: method,
                params: body["params"]?.objectValue ?? [:]
            )
        }
        return requests
    }
}

/// Resolved list-row copy. Locale files override manifest strings.
public struct ExtensionCopy: Sendable, Equatable {
    public var name: String
    public var summary: String
    public var inputs: [String]
    public var outputs: [String]

    public init(name: String, summary: String, inputs: [String], outputs: [String]) {
        self.name = name
        self.summary = summary
        self.inputs = inputs
        self.outputs = outputs
    }
}

public enum ExtensionCopyResolver {
    public static func resolve(manifest: ExtensionManifest, strings: [String: String]) -> ExtensionCopy {
        ExtensionCopy(
            name: strings["name"] ?? manifest.name,
            summary: strings["description"] ?? manifest.summary,
            inputs: labels(manifest.io.inputs, prefix: "io.inputs", strings: strings),
            outputs: labels(manifest.io.outputs, prefix: "io.outputs", strings: strings)
        )
    }

    public static func fieldTitle(
        group: String,
        key: String,
        field: ExtensionFieldSchema,
        strings: [String: String]
    ) -> String {
        strings["\(group).\(key).title"] ?? field.title ?? key
    }

    public static func fieldSummary(
        group: String,
        key: String,
        field: ExtensionFieldSchema,
        strings: [String: String]
    ) -> String? {
        strings["\(group).\(key).description"] ?? field.summary
    }

    public static func choiceTitle(
        group: String,
        key: String,
        choice: ExtensionChoice,
        strings: [String: String]
    ) -> String {
        strings["\(group).\(key).oneOf.\(choice.value)"] ?? choice.title
    }

    private static func labels(
        _ items: [ExtensionIOItem],
        prefix: String,
        strings: [String: String]
    ) -> [String] {
        items.map { item in
            strings["\(prefix).\(item.id)"] ?? item.kind
        }
    }
}

/// Host-side check before `aibo.fetch`. Nil means the URL may be requested.
public enum ExtensionURLPolicy {
    public static func rejection(urlString: String, allowedHosts: Set<String>) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased(), !host.isEmpty else {
            return "invalid-url"
        }
        guard url.scheme?.lowercased() == "https" else {
            return "https-only"
        }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") {
            return "local-host"
        }
        if isBlockedAddress(host) {
            return "private-address"
        }
        let allowed = Set(allowedHosts.map { $0.lowercased() })
        if !allowed.contains(host) {
            return "host-not-allowed"
        }
        return nil
    }

    public static func host(ofURLString string: String) -> String? {
        guard let url = URL(string: string), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host
    }

    private static func isBlockedAddress(_ host: String) -> Bool {
        let stripped = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        if let ipv4 = IPv4(stripped) {
            return ipv4.isBlocked
        }
        // Catch numeric / hex / shortened IPv4 literals (e.g. 2130706433, 0x7f000001, 127.1).
        if isAlternateIPv4Literal(stripped) {
            return true
        }
        if stripped.contains(":") {
            return isBlockedIPv6(stripped)
        }
        return false
    }

    private static func isAlternateIPv4Literal(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return false }
        for part in parts {
            guard !part.isEmpty else { return false }
            if part.hasPrefix("0x") {
                let hex = part.dropFirst(2)
                guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { return false }
            } else {
                guard part.allSatisfy(\.isNumber) else { return false }
            }
        }
        return true
    }

    private static func isBlockedIPv6(_ host: String) -> Bool {
        // Strip optional zone ID (e.g. fe80::1%en0).
        let bare = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        var addr = in6_addr()
        guard inet_pton(AF_INET6, bare, &addr) == 1 else {
            // Malformed IPv6 literal with colon — reject conservatively.
            return true
        }
        let bytes = withUnsafeBytes(of: &addr) { Array($0) }
        guard bytes.count == 16 else { return true }

        // Unspecified `::`
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        // Loopback `::1`
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
        // Unique local `fc00::/7`
        if (bytes[0] & 0xfe) == 0xfc { return true }
        // Link-local `fe80::/10`
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return true }
        // IPv4-mapped `::ffff:0:0/96`
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            let mapped = IPv4(octets: [bytes[12], bytes[13], bytes[14], bytes[15]])
            return mapped.isBlocked
        }
        return false
    }
}

private struct IPv4 {
    var octets: [UInt8]

    init(octets: [UInt8]) {
        self.octets = octets
    }

    init?(_ host: String) {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        self.octets = octets
    }

    var isBlocked: Bool {
        isLoopback || isPrivate || isLinkLocal || isUnspecified || isCGNAT
    }

    var isLoopback: Bool { octets[0] == 127 }
    var isUnspecified: Bool { octets[0] == 0 }
    var isCGNAT: Bool { octets[0] == 100 && (64...127).contains(octets[1]) }
    var isPrivate: Bool {
        if octets[0] == 10 { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        return false
    }

    var isLinkLocal: Bool { octets[0] == 169 && octets[1] == 254 }
}
