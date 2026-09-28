import Foundation

/// Codex-only mapping table. Unknown events return `nil` (no state change).
public enum CodexEventMapper {
    public static func transition(
        eventName: String,
        toolName: String? = nil,
        permissionMode: String? = nil,
        agent: AgentKind = .codex,
        command: String? = nil
    ) -> StateTransition? {
        let isPlanMode = Self.isPlanMode(permissionMode)
        switch eventName {
        case "SessionStart":
            // New / resumed thread with no user turn yet — not “is thinking”.
            return .apply(.registered)
        case "UserPromptSubmit", "SubagentStart":
            return .apply(.thinking)
        case "PreToolUse":
            // Codex network / filesystem grant UI — not “is using request_permissions”.
            if agent == .codex, isRequestPermissionsTool(toolName) {
                return .apply(.waiting)
            }
            // Plan-mode checklist tool — show as planning, not “is using update_plan”.
            if isPlanMode || isUpdatePlanTool(toolName) {
                return .apply(.thinking)
            }
            return .apply(.usingTool(toolName ?? "tool"))
        case "PostToolUse":
            return .apply(.thinking)
        case "PermissionRequest":
            // Command approvals (Bash / apply_patch) all carry `tool_input.command`.
            // That shape is a normal command, including when Codex auto-reviews it.
            // Asks without a command (ExitPlanMode, request_permissions) stay waiting.
            if agent == .codex, isCommandPermissionRequest(toolName: toolName, command: command) {
                return .apply(.usingTool(displayedToolName(toolName)))
            }
            return .apply(.waiting)
        case "Stop", "SubagentStop":
            return .apply(.done)
        case "SessionEnd":
            return .removeSession
        default:
            return nil
        }
    }

    /// Whether the bubble should use “is planning” instead of “is thinking”.
    public static func prefersPlanningCopy(
        eventName: String,
        toolName: String? = nil,
        permissionMode: String? = nil
    ) -> Bool {
        if isUpdatePlanTool(toolName) { return true }
        guard isPlanMode(permissionMode) else { return false }
        switch eventName {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart":
            return true
        default:
            return false
        }
    }

    private static func isPlanMode(_ permissionMode: String?) -> Bool {
        permissionMode?.caseInsensitiveCompare("plan") == .orderedSame
    }

    private static func isUpdatePlanTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        return toolName == "update_plan" || toolName == "UpdatePlan"
    }

    private static func isRequestPermissionsTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        return toolName.caseInsensitiveCompare("request_permissions") == .orderedSame
            || toolName.caseInsensitiveCompare("RequestPermissions") == .orderedSame
    }

    /// Shared shape of the sampled command approvals: a concrete `tool_input.command`.
    /// Prompt tools stay on request even if a command string is also present.
    private static func isCommandPermissionRequest(toolName: String?, command: String?) -> Bool {
        if isUserPromptTool(toolName) { return false }
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    private static func isUserPromptTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        if isRequestPermissionsTool(toolName) { return true }
        switch toolName.lowercased() {
        case "exitplanmode", "exit_plan_mode", "request_user_input":
            return true
        default:
            return false
        }
    }

    private static func displayedToolName(_ toolName: String?) -> String {
        let trimmed = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "tool" : trimmed
    }
}
