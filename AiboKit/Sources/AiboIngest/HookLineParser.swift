import Foundation

/// Dispatches a raw NDJSON hook line to the Cursor or Codex adapter.
public enum HookLineParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }

        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["hookEventName"] as? String)
        let hasSessionID = ((payload["session_id"] as? String)?.isEmpty == false)
        let hasConversationID = ((payload["conversation_id"] as? String)?.isEmpty == false)

        // Cursor: camelCase events (`preToolUse`). Codex: PascalCase (`PreToolUse`).
        // ChatGPT Desktop may include both id fields — event casing is the stable signal.
        // Cursor may also emit `session_id`; never route camelCase into Codex.
        if let eventName, isCodexStyleEventName(eventName), hasSessionID {
            return CodexHookParser.parse(payload: payload)
        }
        if hasConversationID || (eventName.map(isCursorStyleEventName) == true) {
            return try CursorHookParser.parse(jsonLine: jsonLine)
        }
        if hasSessionID {
            return CodexHookParser.parse(payload: payload)
        }
        return nil
    }

    /// Codex hook names are PascalCase (`SessionStart`, `PreToolUse`, …).
    static func isCodexStyleEventName(_ eventName: String) -> Bool {
        guard let first = eventName.first else { return false }
        return first.isUppercase && first.isLetter
    }

    /// Cursor hook names are camelCase (`sessionStart`, `preToolUse`, …).
    static func isCursorStyleEventName(_ eventName: String) -> Bool {
        guard let first = eventName.first else { return false }
        return first.isLowercase && first.isLetter
    }
}
