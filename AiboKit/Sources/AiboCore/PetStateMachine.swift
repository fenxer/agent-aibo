import Foundation

public enum StateTransition: Equatable, Sendable {
    case apply(PetActivityState)
    case removeSession
}

public enum PetEvent: Equatable, Sendable {
    case agent(session: SessionKey, transition: StateTransition, at: Date)
    /// Force idle when a session has been silent longer than `timeout`.
    case watchdog(at: Date, timeout: TimeInterval)
    /// Apply delayed terminal-status → `.idle` fallbacks that are due.
    case idleDeadline(at: Date)
}

public enum PetStateMachine {
    /// Hold time before `.done` / `.registered` / `.interrupted` falls back to `.idle`.
    public static let doneIdleDelay: TimeInterval = 3
    /// Hold time after `.responding` when Cursor never sends `stop` / `sessionEnd`.
    public static let respondingIdleDelay: TimeInterval = 60
    /// Hold time after `.waiting` (approval) with no follow-up hook.
    ///
    /// Codex does not fire `Stop` on user interrupt while a permission prompt is
    /// open, so approval bubbles would otherwise stick until the watchdog.
    public static let waitingIdleDelay: TimeInterval = 60
    /// Default silence timeout before a session is forced to `.idle`.
    public static let defaultWatchdogTimeout: TimeInterval = 120

    /// Auto-clear delay for statuses that linger then fall back to `.idle`.
    public static func idleFallbackDelay(for activity: PetActivityState) -> TimeInterval? {
        switch activity {
        case .done, .registered, .interrupted: doneIdleDelay
        case .responding: respondingIdleDelay
        case .waiting: waitingIdleDelay
        default: nil
        }
    }

    /// Statuses that briefly linger on the bubble, then clear themselves.
    public static func schedulesIdleFallback(_ activity: PetActivityState) -> Bool {
        idleFallbackDelay(for: activity) != nil
    }

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
            let idleAt = idleFallbackDelay(for: activity).map { at.addingTimeInterval($0) }
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
