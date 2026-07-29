import Foundation

/// Cursor-only mapping table. Unknown events return `nil` (no state change).
public enum CursorEventMapper {
    public static func transition(
        eventName: String,
        toolName: String? = nil,
        stopStatus: String? = nil
    ) -> StateTransition? {
        switch eventName {
        case "sessionStart":
            return .apply(.registered)
        case "beforeSubmitPrompt":
            return .apply(.thinking)
        case "preToolUse", "beforeShellExecution", "beforeMCPExecution":
            return .apply(.usingTool(toolName ?? "tool"))
        case "postToolUse", "afterShellExecution", "afterMCPExecution":
            return .apply(.thinking)
        case "postToolUseFailure":
            return .apply(.thinking)
        case "afterAgentResponse":
            return .apply(.responding)
        case "afterAgentThought":
            return nil
        case "subagentStart":
            return .apply(.thinking)
        case "stop", "subagentStop":
            switch stopStatus {
            case "completed", .none:
                return .apply(.done)
            case "aborted":
                return .apply(.interrupted)
            case "error":
                return .apply(.failed)
            default:
                return .apply(.done)
            }
        case "sessionEnd":
            return .removeSession
        default:
            return nil
        }
    }
}
