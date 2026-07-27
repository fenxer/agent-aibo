import AiboCore
import Testing
@testable import AiboIngest

@Test func parserMapsCursorPayload() throws {
    let line = """
    {"conversation_id":"abc","hook_event_name":"preToolUse","tool_name":"Shell","workspace_roots":["/tmp"]}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed?.session == SessionKey(agent: .cursor, conversationID: "abc"))
    #expect(parsed?.transition == .apply(.usingTool("Shell")))
}

@Test func parserIgnoresUnknownEvents() throws {
    let line = """
    {"conversation_id":"abc","hook_event_name":"afterAgentThought"}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed == nil)
}
