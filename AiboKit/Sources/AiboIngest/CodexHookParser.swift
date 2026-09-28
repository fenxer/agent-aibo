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
            permissionMode: permissionMode,
            agent: agent,
            command: commandText(from: payload)
        ) else {
            return nil
        }

        let prefersPlanning = CodexEventMapper.prefersPlanningCopy(
            eventName: eventName,
            toolName: toolName,
            permissionMode: permissionMode
        )

        // Codex only: surface the tool under review. DeepSeek keeps generic waiting copy.
        // Command-shaped approvals are `.usingTool` and do not carry a waiting name.
        let waitingToolName: String? = {
            guard agent == .codex, eventName == "PermissionRequest" else { return nil }
            guard case .apply(.waiting) = transition else { return nil }
            let trimmed = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()

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
            ),
            planProgress: HookPayloadFields.codexUpdatePlanProgress(
                toolName: toolName,
                payload: payload
            ),
            waitingToolName: waitingToolName
        )
    }

    /// `tool_input.command` on Bash / apply_patch permission hooks.
    private static func commandText(from payload: [String: Any]) -> String? {
        guard let input = payload["tool_input"] as? [String: Any] else { return nil }
        guard let command = input["command"] as? String else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
