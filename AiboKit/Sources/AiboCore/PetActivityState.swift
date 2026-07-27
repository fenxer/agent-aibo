import Foundation

public enum AgentKind: String, Sendable, Codable, CaseIterable {
    case cursor
    case codex
}

public enum PetActivityState: Equatable, Sendable, Codable {
    case idle
    case registered
    case thinking
    case usingTool(String)
    case responding
    case waiting
    case done
    case interrupted
    case failed
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
    public var activity: PetActivityState
    public var lastEventAt: Date
    /// When non-nil, the session should fall back to `.idle` at this time after `.done`.
    public var idleAt: Date?

    public init(activity: PetActivityState, lastEventAt: Date, idleAt: Date? = nil) {
        self.activity = activity
        self.lastEventAt = lastEventAt
        self.idleAt = idleAt
    }
}

public struct PetWorldState: Equatable, Sendable, Codable {
    public var sessions: [SessionKey: SessionSnapshot]

    public init(sessions: [SessionKey: SessionSnapshot] = [:]) {
        self.sessions = sessions
    }

    /// Primary session for the pet bubble: waiting > active work > done > idle.
    public var primarySession: (key: SessionKey, snapshot: SessionSnapshot)? {
        let ranked = sessions.sorted { lhs, rhs in
            let left = Self.priority(lhs.value.activity)
            let right = Self.priority(rhs.value.activity)
            if left != right { return left > right }
            return lhs.value.lastEventAt > rhs.value.lastEventAt
        }
        return ranked.first.map { ($0.key, $0.value) }
    }

    private static func priority(_ state: PetActivityState) -> Int {
        switch state {
        case .waiting: 100
        case .usingTool: 80
        case .thinking, .responding, .registered: 60
        case .failed, .interrupted: 40
        case .done: 20
        case .idle: 0
        }
    }
}
