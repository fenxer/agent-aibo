import Foundation
import Testing
@testable import AiboCore

@Test func stateMachineAppliesAndRemovesSessions() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 1_000)

    var state = PetWorldState()
    state = PetStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.thinking), at: t0)
    )
    #expect(state.sessions[key]?.activity == .thinking)

    state = PetStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .removeSession, at: t0.addingTimeInterval(1))
    )
    #expect(state.sessions[key] == nil)
}

@Test func doneSchedulesIdleFallback() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 2_000)

    var state = PetWorldState()
    state = PetStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.done), at: t0)
    )
    #expect(state.sessions[key]?.activity == .done)

    state = PetStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(PetStateMachine.doneIdleDelay - 0.1))
    )
    #expect(state.sessions[key]?.activity == .done)

    state = PetStateMachine.reduce(
        state,
        event: .idleDeadline(at: t0.addingTimeInterval(PetStateMachine.doneIdleDelay))
    )
    #expect(state.sessions[key]?.activity == .idle)
}

@Test func watchdogForcesIdleAfterSilence() {
    let key = SessionKey(agent: .cursor, conversationID: "c1")
    let t0 = Date(timeIntervalSince1970: 3_000)

    var state = PetWorldState()
    state = PetStateMachine.reduce(
        state,
        event: .agent(session: key, transition: .apply(.thinking), at: t0)
    )
    state = PetStateMachine.reduce(
        state,
        event: .watchdog(at: t0.addingTimeInterval(119), timeout: 120)
    )
    #expect(state.sessions[key]?.activity == .thinking)

    state = PetStateMachine.reduce(
        state,
        event: .watchdog(at: t0.addingTimeInterval(120), timeout: 120)
    )
    #expect(state.sessions[key]?.activity == .idle)
}
