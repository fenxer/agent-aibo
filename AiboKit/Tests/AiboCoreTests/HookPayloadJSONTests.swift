import Testing
@testable import AiboCore

@Test func hookPayloadJSONPrettyPrintsObject() {
    let raw = #"{"hook_event_name":"preToolUse","tool_name":"Shell"}"#
    let pretty = HookPayloadJSON.prettyPrinted(raw)
    #expect(pretty.contains("\n"))
    #expect(pretty.contains("\"hook_event_name\""))
    #expect(pretty.contains("preToolUse"))
    #expect(!pretty.contains("\\/"))
}

@Test func hookPayloadJSONLeavesInvalidInputUnchanged() {
    let raw = "not-json"
    #expect(HookPayloadJSON.prettyPrinted(raw) == raw)
}

@Test func hookPayloadJSONLeavesEmptyInputUnchanged() {
    #expect(HookPayloadJSON.prettyPrinted("") == "")
    #expect(HookPayloadJSON.prettyPrinted("   ") == "   ")
}
