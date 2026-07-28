import Foundation

/// Turns a raw webhook body into bubble fields without LLM rewriting.
public enum WebhookMessageFormatter {
    public static let maxLength = 280

    public struct ParsedMessage: Equatable, Sendable {
        public var source: String
        /// Raw `status` when present (shown in the webhook capsule).
        public var status: String?
        /// Prefer `summary`, then `message` / `text` (shown beside the capsule).
        public var summary: String?
        /// Combined line for receive log / fallbacks (`STATUS: summary` when both exist).
        public var displayText: String

        public init(
            source: String,
            status: String? = nil,
            summary: String? = nil,
            displayText: String
        ) {
            self.source = source
            self.status = status
            self.summary = summary
            self.displayText = displayText
        }
    }

    public static func displayText(from body: Data) -> String {
        parse(from: body).displayText
    }

    public static func parse(from body: Data) -> ParsedMessage {
        if let object = try? JSONSerialization.jsonObject(with: body) {
            if let dictionary = object as? [String: Any] {
                let source = sourceLabel(from: dictionary)
                let status = nonEmptyString(dictionary["status"])
                let summary = summaryField(from: dictionary)
                if let text = text(fromJSON: dictionary) {
                    return ParsedMessage(
                        source: source,
                        status: status,
                        summary: summary.map(truncate) ?? truncate(text),
                        displayText: truncate(text)
                    )
                }
                return ParsedMessage(
                    source: source,
                    status: status,
                    summary: summary.map(truncate),
                    displayText: "Webhook received"
                )
            }
            if let text = text(fromJSON: object) {
                return ParsedMessage(
                    source: "Webhook",
                    summary: truncate(text),
                    displayText: truncate(text)
                )
            }
        }
        if let string = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty
        {
            return ParsedMessage(
                source: "Webhook",
                summary: truncate(string),
                displayText: truncate(string)
            )
        }
        return ParsedMessage(source: "Webhook", displayText: "Webhook received")
    }

    /// Prefer explicit sender fields, then event type, else generic Webhook.
    public static func sourceLabel(from dictionary: [String: Any]) -> String {
        if let source = stringValue(dictionary["source"]), !source.isEmpty {
            return source
        }
        if let sender = stringValue(dictionary["sender"]), !sender.isEmpty {
            return sender
        }
        if let from = stringValue(dictionary["from"]), !from.isEmpty {
            return from
        }
        if let event = stringValue(dictionary["event"]), !event.isEmpty {
            if event.hasPrefix("cf.workersBuilds") || event.contains("workersBuilds") {
                return "Cloudflare Workers"
            }
            if event == "statusChange" {
                return "Cursor"
            }
            return event
        }
        return "Webhook"
    }

    private static func summaryField(from dictionary: [String: Any]) -> String? {
        if let summary = nonEmptyString(dictionary["summary"]) {
            return summary
        }
        if let message = nonEmptyString(dictionary["message"]) {
            return message
        }
        if let text = nonEmptyString(dictionary["text"]) {
            return text
        }
        return nil
    }

    private static func text(fromJSON object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let summary = stringValue(dictionary["summary"]), !summary.isEmpty {
                if let status = stringValue(dictionary["status"]), !status.isEmpty {
                    return "\(status): \(summary)"
                }
                return summary
            }
            if let message = stringValue(dictionary["message"]), !message.isEmpty {
                return message
            }
            if let text = stringValue(dictionary["text"]), !text.isEmpty {
                return text
            }
            if let status = stringValue(dictionary["status"]), !status.isEmpty {
                if let event = stringValue(dictionary["event"]), !event.isEmpty {
                    return "\(event): \(status)"
                }
                return status
            }
            if let data = try? JSONSerialization.data(withJSONObject: dictionary),
               let pretty = String(data: data, encoding: .utf8)
            {
                return pretty
            }
            return nil
        }
        if let array = object as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array),
           let pretty = String(data: data, encoding: .utf8)
        {
            return pretty
        }
        if let string = object as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = stringValue(value), !string.isEmpty else { return nil }
        return string
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength - 1)
        return String(text[..<end]) + "…"
    }
}
