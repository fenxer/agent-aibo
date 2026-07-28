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
            return "is waiting for you"
        case .done:
            return "finished"
        case .interrupted:
            return "was interrupted"
        case .failed:
            return "failed"
        }
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }
}
