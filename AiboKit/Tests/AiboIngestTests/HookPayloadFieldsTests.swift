import Testing
@testable import AiboIngest

@Test func subagentIDParsesNestedTranscriptPath() {
    let path = "/Users/me/.cursor/projects/x/agent-transcripts/parent/subagents/abc-123.jsonl"
    #expect(HookPayloadFields.subagentID(fromTranscriptPath: path) == "abc-123")
    #expect(HookPayloadFields.isSubagentTranscript(path) == true)
}

@Test func subagentIDRejectsParentTranscriptPath() {
    let path = "/Users/me/.cursor/projects/x/agent-transcripts/abc-123/abc-123.jsonl"
    #expect(HookPayloadFields.subagentID(fromTranscriptPath: path) == nil)
    #expect(HookPayloadFields.isSubagentTranscript(path) == false)
}
