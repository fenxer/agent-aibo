import Foundation

/// Codex-only mapping table. Unknown events return `nil` (no state change).
public enum CodexEventMapper {
    public static func transition(
        eventName: String,
        toolName: String? = nil,
        permissionMode: String? = nil
    ) -> StateTransition? {
        let isPlanMode = Self.isPlanMode(permissionMode)
        switch eventName {
        case "SessionStart":
            // New / resumed thread with no user turn yet — not “is thinking”.
            return .apply(.registered)
        case "UserPromptSubmit", "SubagentStart":
            return .apply(.thinking)
        case "PreToolUse":
            // Plan-mode checklist tool — show as planning, not “is using update_plan”.
            if isPlanMode || isUpdatePlanTool(toolName) {
                return .apply(.thinking)
            }
            return .apply(.usingTool(toolName ?? "tool"))
        case "PostToolUse":
            return .apply(.thinking)
        case "PermissionRequest":
            // Includes ExitPlanMode and shell/file prompts — same wait state.
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
}
