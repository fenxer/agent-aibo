import Testing
@testable import AiboCore

@Test func cursorMapsCoreEvents() {
    #expect(CursorEventMapper.transition(eventName: "sessionStart") == .apply(.registered))
    #expect(CursorEventMapper.transition(eventName: "beforeSubmitPrompt") == .apply(.thinking))
    #expect(
        CursorEventMapper.transition(eventName: "preToolUse", toolName: "Shell")
            == .apply(.usingTool("Shell"))
    )
    #expect(CursorEventMapper.transition(eventName: "postToolUse") == .apply(.thinking))
    #expect(CursorEventMapper.transition(eventName: "afterAgentResponse") == .apply(.responding))
    #expect(CursorEventMapper.transition(eventName: "afterAgentThought") == nil)
    #expect(
        CursorEventMapper.transition(eventName: "stop", stopStatus: "completed") == .apply(.done)
    )
    #expect(
        CursorEventMapper.transition(eventName: "stop", stopStatus: "aborted")
            == .apply(.interrupted)
    )
    #expect(
        CursorEventMapper.transition(eventName: "stop", stopStatus: "error") == .apply(.failed)
    )
    #expect(CursorEventMapper.transition(eventName: "sessionEnd") == .removeSession)
    #expect(CursorEventMapper.transition(eventName: "unknownEvent") == nil)
}
