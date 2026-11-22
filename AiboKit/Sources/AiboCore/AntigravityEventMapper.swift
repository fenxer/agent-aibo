import Foundation

/// Antigravity-only mapping table. Unknown events return `nil` (no state change).
///
/// There is no approval-wait event. `PreToolUse` is display-only: the hook
/// process prints nothing, so Auto keeps deciding whether the tool runs.
public enum AntigravityEventMapper {
    public static func transition(
        eventName: String,
        toolName: String? = nil,
        terminationReason: String? = nil
    ) -> StateTransition? {
        switch eventName {
        case "SessionStart":
            return .apply(.registered)
        case "PreInvocation":
            return .apply(.thinking)
        case "PreToolUse":
            return .apply(.usingTool(displayedToolName(toolName)))
        case "PostToolUse":
            return .apply(.thinking)
        case "Stop":
            switch normalized(terminationReason) {
            case "error":
                return .apply(.failed)
            case "user_canceled", "user_cancelled", "canceled", "cancelled":
                return .apply(.interrupted)
            default:
                return .apply(.done)
            }
        default:
            return nil
        }
    }

    private static func normalized(_ reason: String?) -> String {
        reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func displayedToolName(_ toolName: String?) -> String {
        let trimmed = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "tool" : trimmed
    }
}
