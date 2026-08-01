import Foundation

/// Local templates for agent status. Never call an LLM from this path.
public enum StatusCopy {
    /// Full sentence used by non-bubble callers (e.g. LLM helpers).
    public static func message(
        for activity: PetActivityState,
        agent: AgentKind
    ) -> String? {
        guard let phrase = statusPhrase(for: activity) else { return nil }
        return "\(displayName(agent)) \(phrase)"
    }

    /// Status text shown beside the agent capsule (no agent name prefix).
    public static func statusPhrase(for activity: PetActivityState) -> String? {
        switch activity {
        case .idle:
            return nil
        case .registered:
            return "session started"
        case .thinking:
            return "is thinking"
        case let .usingTool(name):
            return "is using \(name)"
        case .responding:
            return "is responding"
        case .waiting:
            return "needs your approval"
        case .done:
            return "finished"
        case .interrupted:
            return "was interrupted"
        case .failed:
            return "failed"
        }
    }

    /// Bubble-style example under a hook name in Settings → Sprite Actions.
    ///
    /// Uses the same phrases as live bubbles (`statusPhrase`), with sample tool names.
    public static func exampleBubblePhrase(
        agent: AgentKind,
        hookEventName: String
    ) -> String? {
        // Cursor `stop` maps to done / interrupted / failed depending on status.
        if agent == .cursor, hookEventName == "stop" {
            return "finished · was interrupted · failed"
        }

        let transition: StateTransition?
        switch agent {
        case .cursor:
            transition = CursorEventMapper.transition(
                eventName: hookEventName,
                toolName: "Shell",
                stopStatus: "completed"
            )
        case .codex:
            transition = CodexEventMapper.transition(
                eventName: hookEventName,
                toolName: "Bash"
            )
        }

        switch transition {
        case .apply(let activity):
            return statusPhrase(for: activity)
        case .removeSession:
            return "clears session"
        case nil:
            return nil
        }
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }
}
