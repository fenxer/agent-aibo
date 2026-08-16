import AiboCore

/// Model provider abstractions used for remote webhook persona rewriting.
public enum AiboLLM {
    public static let moduleName = "AiboLLM"

    /// Placeholder dependency edge so the module stays wired to AiboCore.
    public static func statusLabel(for activity: AiboActivityState, agent: AgentKind) -> String? {
        StatusCopy.message(for: activity, agent: agent)
    }
}
