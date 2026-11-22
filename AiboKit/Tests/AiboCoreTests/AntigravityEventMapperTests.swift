import Testing
@testable import AiboCore

@Test func antigravityEventsMapToDisplayStates() {
    #expect(AntigravityEventMapper.transition(eventName: "SessionStart") == .apply(.registered))
    #expect(AntigravityEventMapper.transition(eventName: "PreInvocation") == .apply(.thinking))
    #expect(
        AntigravityEventMapper.transition(eventName: "PreToolUse", toolName: "run_command")
            == .apply(.usingTool("run_command"))
    )
    #expect(
        AntigravityEventMapper.transition(eventName: "PreToolUse", toolName: "  ")
            == .apply(.usingTool("tool"))
    )
    #expect(AntigravityEventMapper.transition(eventName: "PostToolUse") == .apply(.thinking))
    #expect(
        AntigravityEventMapper.transition(eventName: "Stop", terminationReason: "model_stop")
            == .apply(.done)
    )
    #expect(
        AntigravityEventMapper.transition(eventName: "Stop", terminationReason: "ERROR")
            == .apply(.failed)
    )
    #expect(
        AntigravityEventMapper.transition(eventName: "Stop", terminationReason: "USER_CANCELED")
            == .apply(.interrupted)
    )
    #expect(AntigravityEventMapper.transition(eventName: "SessionEnd") == nil)
    #expect(AgentKind.antigravity.supportsPlanProgress == false)
}
