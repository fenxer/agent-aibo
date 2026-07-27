import Foundation

/// Dispatches a raw NDJSON hook line to the Cursor or Codex adapter.
public enum HookLineParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }

        // Cursor uses conversation_id; Codex uses session_id.
        if let conversationID = payload["conversation_id"] as? String, !conversationID.isEmpty {
            return try CursorHookParser.parse(jsonLine: jsonLine)
        }
        if let sessionID = payload["session_id"] as? String, !sessionID.isEmpty {
            return CodexHookParser.parse(payload: payload)
        }
        return nil
    }
}
