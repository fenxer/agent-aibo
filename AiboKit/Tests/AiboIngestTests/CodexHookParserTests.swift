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
    #expect(parsed?.prefersPlanningCopy == false)
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

@Test func parserIgnoresEmptyCodexUserPromptSubmit() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"UserPromptSubmit","prompt":"  "}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed == nil)
}

@Test func parserMapsCodexPlanModePromptToPlanningCopy() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"UserPromptSubmit","prompt":"plan the fix","permission_mode":"plan","cwd":"/tmp/aibo"}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed?.transition == .apply(.thinking))
    #expect(parsed?.prefersPlanningCopy == true)
}

@Test func parserLogsCodexUpdatePlanToolInputInIngestDetail() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"PreToolUse","tool_name":"update_plan","tool_input":{"explanation":"track work","plan":[{"step":"Parse hooks","status":"completed"},{"step":"Log todos","status":"in_progress"},{"step":"Show bubble","status":"pending"}]}}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed?.transition == .apply(.thinking))
    #expect(parsed?.prefersPlanningCopy == true)
    #expect(parsed?.ingestDetail == "update_plan explanation=track work steps=3 [completed] Parse hooks | [in_progress] Log todos | [pending] Show bubble")
}

@Test func parserLogsMissingUpdatePlanToolInput() throws {
    let line = """
    {"session_id":"thr_123","hook_event_name":"PreToolUse","tool_name":"update_plan"}
    """
    let parsed = try CodexHookParser.parse(jsonLine: line)
    #expect(parsed?.ingestDetail == "update_plan tool_input=missing")
}

@Test func hookLineParserPrefersCodexSessionIDWhenBothPresent() throws {
    // ChatGPT Desktop (merged Codex) may include conversation_id alongside session_id.
    let both = """
    {"session_id":"thr_1","conversation_id":"conv_should_ignore","hook_event_name":"UserPromptSubmit","prompt":"hi"}
    """
    let parsed = try HookLineParser.parse(jsonLine: both)
    #expect(parsed?.session.agent == .codex)
    #expect(parsed?.session.conversationID == "thr_1")
    #expect(parsed?.transition == .apply(.thinking))
}

@Test func hookLineParserDispatchesBySessionKeyField() throws {
    let cursor = """
    {"conversation_id":"abc","hook_event_name":"beforeSubmitPrompt"}
    """
    let codex = """
    {"session_id":"thr_1","hook_event_name":"UserPromptSubmit","prompt":"hi"}
    """
    let cursorParsed = try HookLineParser.parse(jsonLine: cursor)
    let codexParsed = try HookLineParser.parse(jsonLine: codex)
    #expect(cursorParsed?.session.agent == .cursor)
    #expect(codexParsed?.session.agent == .codex)
    #expect(cursorParsed?.transition == .apply(.thinking))
    #expect(codexParsed?.transition == .apply(.thinking))
}
