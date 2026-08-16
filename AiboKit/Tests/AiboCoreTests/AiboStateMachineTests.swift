import Foundation
import Testing
@testable import AiboCore

@Test func stateMachineAppliesAndRemovesSessions() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 1_000)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.thinking), at: t0)
    )
    #expect(state.sessions[key]?.activity == .thinking)

    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .removeSession, at: t0.addingTimeInterval(1))
    )
    #expect(state.sessions[key] == nil)
}

@Test func doneSchedulesIdleFallback() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 2_000)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.done), at: t0)
    )
    #expect(state.sessions[key]?.activity == .done)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.doneIdleDelay - 0.1))
    )
    #expect(state.sessions[key]?.activity == .done)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.doneIdleDelay))
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func registeredSchedulesIdleFallback() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 2_500)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.registered), at: t0)
    )
    #expect(state.sessions[key]?.activity == .registered)
    #expect(state.sessions[key]?.idleAt == t0.addingTimeInterval(AiboStateMachine.doneIdleDelay))

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.doneIdleDelay - 0.1))
    )
    #expect(state.sessions[key]?.activity == .registered)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.doneIdleDelay))
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func interruptedSchedulesIdleFallback() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 2_750)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.interrupted), at: t0)
    )
    #expect(state.sessions[key]?.activity == .interrupted)
    #expect(state.sessions[key]?.idleAt == t0.addingTimeInterval(AiboStateMachine.doneIdleDelay))

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.doneIdleDelay))
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func waitingSchedulesIdleFallback() {
    let key = SessionKey(agent: .codex, conversationID: "thr_1")
    let t0 = Date(timeIntervalSince1970: 2_760)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.waiting), at: t0)
    )
    #expect(state.sessions[key]?.activity == .waiting)
    #expect(
        state.sessions[key]?.idleAt
            == t0.addingTimeInterval(AiboStateMachine.waitingIdleDelay)
    )
    #expect(AiboStateMachine.idleFallbackDelay(for: .waiting) == 60)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.waitingIdleDelay - 0.1))
    )
    #expect(state.sessions[key]?.activity == .waiting)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.waitingIdleDelay))
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func failedDoesNotScheduleIdleFallback() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 2_800)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.failed), at: t0)
    )
    #expect(state.sessions[key]?.activity == .failed)
    #expect(state.sessions[key]?.idleAt == nil)
    #expect(AiboStateMachine.schedulesIdleFallback(.failed) == false)
}

@Test func respondingSchedulesOneMinuteIdleFallback() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 2_900)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.responding), at: t0)
    )
    #expect(state.sessions[key]?.activity == .responding)
    #expect(
        state.sessions[key]?.idleAt
            == t0.addingTimeInterval(AiboStateMachine.respondingIdleDelay)
    )
    #expect(AiboStateMachine.idleFallbackDelay(for: .responding) == 60)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.respondingIdleDelay - 0.1))
    )
    #expect(state.sessions[key]?.activity == .responding)

    state = AiboStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(AiboStateMachine.respondingIdleDelay))
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func watchdogForcesIdleAfterSilence() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 3_000)

    var state = AiboWorldState()
    state = AiboStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.thinking), at: t0)
    )
    state = AiboStateMachine.reduce(
        state,
        event: .watchdog(at: t0.addingTimeInterval(119), timeout: 120)
    )
    #expect(state.sessions[key]?.activity == .thinking)

    state = AiboStateMachine.reduce(
        state,
        event: .watchdog(at: t0.addingTimeInterval(120), timeout: 120)
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func cursorUsingToolStallHintOnlyForCursorUsingToolAfterDelay() {
    let t0 = Date(timeIntervalSince1970: 3_000)
    #expect(AiboStateMachine.cursorUsingToolStallDelay == 10)
    #expect(
        CursorUsingToolStallHint.isDue(
            agent: .cursor,
            activity: .usingTool("Shell"),
            lastEventAt: t0,
            now: t0.addingTimeInterval(9.9)
        ) == false
    )
    #expect(
        CursorUsingToolStallHint.isDue(
            agent: .cursor,
            activity: .usingTool("Shell"),
            lastEventAt: t0,
            now: t0.addingTimeInterval(10)
        )
    )
    #expect(
        CursorUsingToolStallHint.isDue(
            agent: .codex,
            activity: .usingTool("Bash"),
            lastEventAt: t0,
            now: t0.addingTimeInterval(30)
        ) == false
    )
    #expect(
        CursorUsingToolStallHint.isDue(
            agent: .cursor,
            activity: .thinking,
            lastEventAt: t0,
            now: t0.addingTimeInterval(30)
        ) == false
    )
}

@Test func waitingApprovalEscalationHintOnlyAfterDelay() {
    let t0 = Date(timeIntervalSince1970: 4_000)
    #expect(AiboStateMachine.waitingApprovalEscalationDelay == 5)
    #expect(
        WaitingApprovalEscalationHint.isDue(
            activity: .waiting,
            lastEventAt: t0,
            now: t0.addingTimeInterval(4.9)
        ) == false
    )
    #expect(
        WaitingApprovalEscalationHint.isDue(
            activity: .waiting,
            lastEventAt: t0,
            now: t0.addingTimeInterval(5)
        )
    )
    #expect(
        WaitingApprovalEscalationHint.isDue(
            activity: .thinking,
            lastEventAt: t0,
            now: t0.addingTimeInterval(30)
        ) == false
    )
}
