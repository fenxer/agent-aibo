import AiboCore
import Testing
@testable import AiboIngest

@Test func parserMapsCodexPayload() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/tmp/aibo"}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed?.session == SessionKey(agent: .codex, conversationID: "thr_123"))
    #expect(parsed?.transition == .apply(.usingTool("Bash")))
    #expect(parsed?.projectName == "aibo")
}

@Test func parserMapsCodexPermissionRequestToWaiting() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"PermissionRequest","tool_name":"Bash"}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed?.transition == .apply(.waiting))
}

@Test func parserMapsCodexSubagentStopToDone() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"SubagentStop","agent_type":"explore"}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed?.transition == .apply(.done))
}

@Test func hookLineParserDispatchesBySessionKeyField() throws {
    let cursor = """
    {"conversation_id":"abc","hook_event_name":"beforeSubmitPrompt"}
    """
    let codex = """
    {"session_id":"thr_1","hook_event_name":"UserPromptSubmit"}
    """
    let cursorParsed = try HookLineParser.parse(jsonLine: cursor)
    let codexParsed = try HookLineParser.parse(jsonLine: codex)
    #expect(cursorParsed?.session.agent == .cursor)
    #expect(codexParsed?.session.agent == .codex)
    #expect(cursorParsed?.transition == .apply(.thinking))
    #expect(codexParsed?.transition == .apply(.thinking))
}
