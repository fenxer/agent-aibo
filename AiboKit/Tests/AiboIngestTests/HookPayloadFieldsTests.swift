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

@Test func codexUpdatePlanIngestDetailSummarizesSteps() {
    let detail = HookPayloadFields.codexUpdatePlanIngestDetail(
        toolName: "update_plan",
        payload: [
            "tool_input": [
                "plan": [
                    ["step": "A", "status": "completed"],
                    ["step": "B", "status": "in_progress"],
                ],
            ] as [String: Any],
        ]
    )
    #expect(detail == "update_plan steps=2 [completed] A | [in_progress] B")
}

@Test func codexUpdatePlanIngestDetailIgnoresOtherTools() {
    let detail = HookPayloadFields.codexUpdatePlanIngestDetail(
        toolName: "Bash",
        payload: [
            "tool_input": ["command": "ls"],
        ]
    )
    #expect(detail == nil)
}
