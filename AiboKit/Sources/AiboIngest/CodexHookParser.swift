import AiboCore
import Foundation

public enum CodexHookParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }
        return parse(payload: payload)
    }

    public static func parse(payload: [String: Any]) -> ParsedHookLine? {
        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["hookEventName"] as? String)
        guard let eventName, !eventName.isEmpty else { return nil }

        guard let sessionID = payload["session_id"] as? String,
              !sessionID.isEmpty
        else {
            return nil
        }

        let toolName = payload["tool_name"] as? String
        guard let transition = CodexEventMapper.transition(
            eventName: eventName,
            toolName: toolName
        ) else {
            return nil
        }

        return ParsedHookLine(
            session: SessionKey(agent: .codex, conversationID: sessionID),
            transition: transition,
            eventName: eventName,
            projectName: HookPayloadFields.projectName(from: payload),
            modelName: HookPayloadFields.modelName(from: payload)
        )
    }
}
