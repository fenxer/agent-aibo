import Testing
@testable import AiboCore

@Test func codexMapsCoreEvents() {
    #expect(CodexEventMapper.transition(eventName: "SessionStart") == .apply(.registered))
    #expect(CodexEventMapper.transition(eventName: "UserPromptSubmit") == .apply(.thinking))
    #expect(
        CodexEventMapper.transition(eventName: "PreToolUse", toolName: "Bash")
            == .apply(.usingTool("Bash"))
    )
    #expect(CodexEventMapper.transition(eventName: "PostToolUse") == .apply(.thinking))
    #expect(CodexEventMapper.transition(eventName: "SubagentStart") == .apply(.thinking))
    #expect(CodexEventMapper.transition(eventName: "PermissionRequest") == .apply(.waiting))
    #expect(CodexEventMapper.transition(eventName: "Stop") == .apply(.done))
    #expect(CodexEventMapper.transition(eventName: "SubagentStop") == .apply(.done))
    #expect(CodexEventMapper.transition(eventName: "SessionEnd") == .removeSession)
    #expect(CodexEventMapper.transition(eventName: "PreCompact") == nil)
}
