import Foundation

/// Codex-only mapping table. Unknown events return `nil` (no state change).
public enum CodexEventMapper {
    public static func transition(
        eventName: String,
        toolName: String? = nil
    ) -> StateTransition? {
        switch eventName {
        case "SessionStart":
            return .apply(.registered)
        case "UserPromptSubmit", "SubagentStart":
            return .apply(.thinking)
        case "PreToolUse":
            return .apply(.usingTool(toolName ?? "tool"))
        case "PostToolUse":
            return .apply(.thinking)
        case "PermissionRequest":
            return .apply(.waiting)
        case "Stop", "SubagentStop":
            return .apply(.done)
        case "SessionEnd":
            return .removeSession
        default:
            return nil
        }
    }
}
