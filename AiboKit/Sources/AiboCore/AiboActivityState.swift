import Foundation

public enum AgentKind: String, Sendable, Codable, CaseIterable {
    case cursor
    case codex
    case deepseek
}

public enum AiboActivityState: Equatable, Sendable, Codable {
    case idle
    case registered
    case thinking
    case usingTool(String)
    case responding
    case waiting
    case done
    case interrupted
    case failed

    /// Terminal hook: keep this animation until the session leaves the state.
    public var isOutcome: Bool {
        switch self {
        case .done, .failed, .interrupted: true
        default: false
        }
    }
}

public struct SessionKey: Hashable, Sendable, Codable {
    public var agent: AgentKind
    public var conversationID: String

    public init(agent: AgentKind, conversationID: String) {
        self.agent = agent
        self.conversationID = conversationID
    }
}

public struct SessionSnapshot: Equatable, Sendable, Codable {
    public var activity: AiboActivityState
    public var lastEventAt: Date
    /// When non-nil, the session should fall back to `.idle` at this time
    /// (used after `.done`, `.registered`, `.interrupted`, `.responding`, and `.waiting`).
    public var idleAt: Date?

    public init(activity: AiboActivityState, lastEventAt: Date, idleAt: Date? = nil) {
        self.activity = activity
        self.lastEventAt = lastEventAt
        self.idleAt = idleAt
    }
}

public struct AiboWorldState: Equatable, Sendable, Codable {
    public var sessions: [SessionKey: SessionSnapshot]

    public init(sessions: [SessionKey: SessionSnapshot] = [:]) {
        self.sessions = sessions
    }

    /// Session driving the sprite: outcome hooks first, else newest non-idle.
    public var primarySession: (key: SessionKey, snapshot: SessionSnapshot)? {
        AiboActionMapping.preferredSession(sessions: sessions)
    }
}
