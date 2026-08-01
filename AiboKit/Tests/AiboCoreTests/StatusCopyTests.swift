import Testing
@testable import AiboCore

@Test func statusCopyExampleBubblePhrasesMatchLiveCopy() {
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .cursor, hookEventName: "sessionStart")
            == "session started"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .cursor, hookEventName: "beforeSubmitPrompt")
            == "is thinking"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .cursor, hookEventName: "preToolUse")
            == "is using Shell"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .cursor, hookEventName: "afterAgentResponse")
            == "is responding"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .cursor, hookEventName: "stop")
            == "finished · was interrupted · failed"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .cursor, hookEventName: "sessionEnd")
            == "clears session"
    )

    #expect(
        StatusCopy.exampleBubblePhrase(agent: .codex, hookEventName: "PreToolUse")
            == "is using Bash"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .codex, hookEventName: "PermissionRequest")
            == "needs your approval"
    )
    #expect(
        StatusCopy.statusPhrase(for: .waiting) == "needs your approval"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .codex, hookEventName: "Stop") == "finished"
    )
}
