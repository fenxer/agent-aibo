import Foundation

/// Local templates for agent status. Never call an LLM from this path.
public enum StatusCopy {
    public static func message(
        for activity: PetActivityState,
        agent: AgentKind
    ) -> String? {
        let agentLabel = displayName(agent)
        switch activity {
        case .idle:
            return nil
        case .registered:
            return "\(agentLabel) session started"
        case .thinking:
            return "\(agentLabel) is thinking…"
        case let .usingTool(name):
            return "\(agentLabel) is using \(name)"
        case .responding:
            return "\(agentLabel) is responding…"
        case .waiting:
            return "\(agentLabel) is waiting for you"
        case .done:
            return "\(agentLabel) finished"
        case .interrupted:
            return "\(agentLabel) was interrupted"
        case .failed:
            return "\(agentLabel) failed"
        }
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }
}
