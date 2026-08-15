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
            == "is reviewing · got stuck?"
    )
    #expect(
        StatusCopy.statusPhrase(for: .waiting) == "is reviewing"
    )
    #expect(StatusCopy.needsYourApprovalPhrase == "got stuck?")
    #expect(StatusCopy.stuckPhrase == "got stuck?")
    #expect(StatusCopy.planningPhrase == "is planning")
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .codex, hookEventName: "Stop") == "finished"
    )
    #expect(
        StatusCopy.exampleBubblePhrase(agent: .deepseek, hookEventName: "UserPromptSubmit")
            == "is thinking"
    )
}

@Test func statusCopyHookSettingDescriptionsExplainTheEvent() {
    #expect(
        StatusCopy.hookSettingDescription(agent: .cursor, hookEventName: "sessionStart")
            == "Starts a new conversation"
    )
    #expect(
        StatusCopy.hookSettingDescription(agent: .cursor, hookEventName: "sessionEnd")
            == "Conversation ended"
    )
    #expect(
        StatusCopy.hookSettingDescription(agent: .cursor, hookEventName: "stop")
            == "This turn ended"
    )
    #expect(
        StatusCopy.hookSettingDescription(agent: .cursor, hookEventName: "preToolUse")
            == "About to use a tool. e.g. is using Shell"
    )
    #expect(
        StatusCopy.hookSettingDescription(agent: .codex, hookEventName: "PermissionRequest")
            == "Waiting for approval or auto-review. e.g. is reviewing, then got stuck?"
    )
    #expect(
        StatusCopy.hookSettingDescription(agent: .deepseek, hookEventName: "UserPromptSubmit")
            == "Submitted a prompt and started thinking. e.g. is planning in plan mode"
    )
}
