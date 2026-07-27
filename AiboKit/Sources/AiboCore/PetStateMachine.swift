import Foundation

public enum StateTransition: Equatable, Sendable {
    case apply(PetActivityState)
    case removeSession
}

public enum PetEvent: Equatable, Sendable {
    case agent(session: SessionKey, transition: StateTransition, at: Date)
    /// Force idle when a session has been silent longer than `timeout`.
    case watchdog(at: Date, timeout: TimeInterval)
    /// Apply delayed `.done` / `.registered` → `.idle` fallbacks that are due.
    case idleDeadline(at: Date)
}

public enum PetStateMachine {
    /// Hold time before `.done` or `.registered` falls back to `.idle`.
    public static let doneIdleDelay: TimeInterval = 3
    /// Default silence timeout before a session is forced to `.idle`.
    public static let defaultWatchdogTimeout: TimeInterval = 120

    public static func reduce(_ state: PetWorldState, event: PetEvent) -> PetWorldState {
        var next = state
        switch event {
        case let .agent(session, transition, at):
            applyAgent(to: &next, session: session, transition: transition, at: at)
        case let .watchdog(at, timeout):
            applyWatchdog(to: &next, at: at, timeout: timeout)
        case let .idleDeadline(at):
            applyIdleDeadlines(to: &next, at: at)
        }
        return next
    }

    private static func applyAgent(
        to state: inout PetWorldState,
        session: SessionKey,
        transition: StateTransition,
        at: Date
    ) {
        switch transition {
        case .removeSession:
            state.sessions.removeValue(forKey: session)
        case let .apply(activity):
            let idleAt: Date?
            switch activity {
            case .done, .registered:
                idleAt = at.addingTimeInterval(doneIdleDelay)
            case .idle:
                idleAt = nil
            default:
                idleAt = nil
            }
            state.sessions[session] = SessionSnapshot(
                activity: activity,
                lastEventAt: at,
                idleAt: idleAt
            )
        }
    }

    private static func applyWatchdog(
        to state: inout PetWorldState,
        at: Date,
        timeout: TimeInterval
    ) {
        for (key, snapshot) in state.sessions {
            guard snapshot.activity != .idle else { continue }
            if at.timeIntervalSince(snapshot.lastEventAt) >= timeout {
                state.sessions[key] = SessionSnapshot(
                    activity: .idle,
                    lastEventAt: at,
                    idleAt: nil
                )
            }
        }
    }

    private static func applyIdleDeadlines(to state: inout PetWorldState, at: Date) {
        for (key, snapshot) in state.sessions {
            guard let idleAt = snapshot.idleAt, at >= idleAt else { continue }
            state.sessions[key] = SessionSnapshot(
                activity: .idle,
                lastEventAt: at,
                idleAt: nil
            )
        }
    }
}
