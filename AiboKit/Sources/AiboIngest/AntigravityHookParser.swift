import AiboCore
import Foundation

public enum AntigravityHookParser {
    public static func parse(payload: [String: Any]) -> ParsedHookLine? {
        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["hookEventName"] as? String)
        guard let eventName, !eventName.isEmpty else { return nil }

        let conversationID = (payload["conversationId"] as? String)
            ?? (payload["conversation_id"] as? String)
        guard let conversationID, !conversationID.isEmpty else { return nil }

        let toolName = toolName(from: payload)
        let terminationReason = payload["terminationReason"] as? String
        guard let transition = AntigravityEventMapper.transition(
            eventName: eventName,
            toolName: toolName,
            terminationReason: terminationReason
        ) else {
            return nil
        }

        return ParsedHookLine(
            session: SessionKey(agent: .antigravity, conversationID: conversationID),
            transition: transition,
            eventName: eventName,
            projectName: projectName(from: payload),
            modelName: HookPayloadFields.modelName(from: payload)
        )
    }

    private static func toolName(from payload: [String: Any]) -> String? {
        if let call = payload["toolCall"] as? [String: Any],
           let name = call["name"] as? String
        {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let name = payload["tool_name"] as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func projectName(from payload: [String: Any]) -> String? {
        if let paths = payload["workspacePaths"] as? [String],
           let first = paths.first,
           !first.isEmpty
        {
            let name = URL(fileURLWithPath: first).lastPathComponent
            if !name.isEmpty { return name }
        }
        return HookPayloadFields.projectName(from: payload)
    }
}
