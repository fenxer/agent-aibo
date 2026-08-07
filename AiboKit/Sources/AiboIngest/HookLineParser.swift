import Foundation

/// Dispatches a raw NDJSON hook line to the Cursor or Codex adapter.
public enum HookLineParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }

        // Codex uses `session_id` + PascalCase events. ChatGPT Desktop (merged
        // Codex) may also include `conversation_id` — prefer session_id so we
        // don't mis-route into the Cursor mapper (which would drop the event).
        if let sessionID = payload["session_id"] as? String, !sessionID.isEmpty {
            return CodexHookParser.parse(payload: payload)
        }
        if let conversationID = payload["conversation_id"] as? String, !conversationID.isEmpty {
            return try CursorHookParser.parse(jsonLine: jsonLine)
        }
        return nil
    }
}
