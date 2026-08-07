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

@Test func codexPlanModeMapsToolsToThinking() {
    #expect(
        CodexEventMapper.transition(
            eventName: "PreToolUse",
            toolName: "Bash",
            permissionMode: "plan"
        ) == .apply(.thinking)
    )
    #expect(
        CodexEventMapper.transition(eventName: "PreToolUse", toolName: "update_plan")
            == .apply(.thinking)
    )
    #expect(
        CodexEventMapper.transition(
            eventName: "PermissionRequest",
            toolName: "ExitPlanMode",
            permissionMode: "plan"
        ) == .apply(.waiting)
    )
    #expect(
        CodexEventMapper.prefersPlanningCopy(
            eventName: "UserPromptSubmit",
            permissionMode: "plan"
        )
    )
    #expect(
        CodexEventMapper.prefersPlanningCopy(eventName: "PreToolUse", toolName: "update_plan")
    )
    #expect(
        !CodexEventMapper.prefersPlanningCopy(eventName: "UserPromptSubmit", permissionMode: "default")
    )
}
