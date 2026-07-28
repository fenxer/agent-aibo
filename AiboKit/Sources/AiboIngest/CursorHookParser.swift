import AiboCore
import Foundation

public struct ParsedHookLine: Sendable, Equatable {
    public var session: SessionKey
    public var transition: StateTransition
    public var eventName: String
    /// Last path component of workspace root / cwd when present in the payload.
    public var projectName: String? = nil
    /// Model id / label when the hook payload includes one.
    public var modelName: String? = nil
}

public enum CursorHookParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }

        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["hookEventName"] as? String)
        guard let eventName, !eventName.isEmpty else { return nil }

        guard let conversationID = payload["conversation_id"] as? String,
              !conversationID.isEmpty
        else {
            return nil
        }

        let toolName = payload["tool_name"] as? String
        let stopStatus = payload["status"] as? String
        guard let transition = CursorEventMapper.transition(
            eventName: eventName,
            toolName: toolName,
            stopStatus: stopStatus
        ) else {
            return nil
        }

        return ParsedHookLine(
            session: SessionKey(agent: .cursor, conversationID: conversationID),
            transition: transition,
            eventName: eventName,
            projectName: HookPayloadFields.projectName(from: payload),
            modelName: HookPayloadFields.modelName(from: payload)
        )
    }
}
