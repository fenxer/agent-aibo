import AiboCore
import Foundation

public enum CodexHookParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }
        return parse(payload: payload)
    }

    public static func parse(
        payload: [String: Any],
        agent: AgentKind = .codex
    ) -> ParsedHookLine? {
        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["hookEventName"] as? String)
        guard let eventName, !eventName.isEmpty else { return nil }

        guard let sessionID = payload["session_id"] as? String,
              !sessionID.isEmpty
        else {
            return nil
        }

        // Empty UserPromptSubmit = no real turn yet (don't flash “is thinking”).
        if eventName == "UserPromptSubmit" {
            let prompt = (payload["prompt"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if prompt.isEmpty { return nil }
        }

        let toolName = payload["tool_name"] as? String
        let permissionMode = payload["permission_mode"] as? String
            ?? payload["permissionMode"] as? String
        guard let transition = CodexEventMapper.transition(
            eventName: eventName,
            toolName: toolName,
            permissionMode: permissionMode
        ) else {
            return nil
        }

        let prefersPlanning = CodexEventMapper.prefersPlanningCopy(
            eventName: eventName,
            toolName: toolName,
            permissionMode: permissionMode
        )

        return ParsedHookLine(
            session: SessionKey(agent: agent, conversationID: sessionID),
            transition: transition,
            eventName: eventName,
            projectName: HookPayloadFields.projectName(from: payload),
            modelName: HookPayloadFields.modelName(from: payload),
            prefersPlanningCopy: prefersPlanning,
            ingestDetail: HookPayloadFields.codexUpdatePlanIngestDetail(
                toolName: toolName,
                payload: payload
            )
        )
    }
}
