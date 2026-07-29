import AiboCore
import Testing
@testable import AiboIngest

@Test func parserMapsCursorPayload() throws {
    let line = """
    {"conversation_id":"abc","hook_event_name":"preToolUse","tool_name":"Shell","workspace_roots":["/tmp/design-fragments"],"model":"Grok 4.5 High Fast"}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed?.session == SessionKey(agent: .cursor, conversationID: "abc"))
    #expect(parsed?.transition == .apply(.usingTool("Shell")))
    #expect(parsed?.projectName == "design-fragments")
    #expect(parsed?.modelName == "Grok 4.5 High Fast")
    #expect(parsed?.isSubagent == false)
}

@Test func parserIgnoresUnknownEvents() throws {
    let line = """
    {"conversation_id":"abc","hook_event_name":"afterAgentThought"}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed == nil)
}

@Test func parserMapsSubagentStartToSubagentSession() throws {
    let line = """
    {"hook_event_name":"subagentStart","subagent_id":"sub-1","parent_conversation_id":"parent-9","subagent_model":"grok-4.5","workspace_roots":["/tmp/design-fragments"],"task":"Explore auth"}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed?.session == SessionKey(agent: .cursor, conversationID: "sub-1"))
    #expect(parsed?.transition == .apply(.thinking))
    #expect(parsed?.isSubagent == true)
    #expect(parsed?.modelName == "grok-4.5")
    #expect(parsed?.projectName == "design-fragments")
}

@Test func parserMapsSubagentStopFromTranscriptPath() throws {
    let line = """
    {"hook_event_name":"subagentStop","status":"completed","agent_transcript_path":"/tmp/agent-transcripts/parent/subagents/sub-1.jsonl","conversation_id":"parent-9"}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed?.session == SessionKey(agent: .cursor, conversationID: "sub-1"))
    #expect(parsed?.transition == .apply(.done))
    #expect(parsed?.isSubagent == true)
}

@Test func parserMarksSubagentFromTranscriptPath() throws {
    let line = """
    {"conversation_id":"sub-1","hook_event_name":"preToolUse","tool_name":"Read","transcript_path":"/tmp/agent-transcripts/parent/subagents/sub-1.jsonl"}
    """
    let parsed = try CursorHookParser.parse(jsonLine: line)
    #expect(parsed?.isSubagent == true)
    #expect(parsed?.transition == .apply(.usingTool("Read")))
}
