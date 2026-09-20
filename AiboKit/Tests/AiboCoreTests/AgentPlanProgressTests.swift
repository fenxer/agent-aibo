import Testing
@testable import AiboCore

@Test func planProgressUsesInProgressIndex() {
    let progress = AgentPlanProgress.fromPlanStatuses(["completed", "in_progress", "pending"])
    #expect(progress == AgentPlanProgress(current: 2, total: 3, completed: 1))
    #expect(progress?.fraction == 1.0 / 3.0)
}

@Test func planProgressFirstStepHasEmptyRing() {
    let progress = AgentPlanProgress.fromPlanStatuses(["in_progress", "pending", "pending"])
    #expect(progress == AgentPlanProgress(current: 1, total: 3, completed: 0))
    #expect(progress?.fraction == 0)
}

@Test func planProgressUsesFirstTodoWhenAllPending() {
    let progress = AgentPlanProgress.fromPlanStatuses(["pending", "pending", "pending"])
    #expect(progress == AgentPlanProgress(current: 1, total: 3, completed: 0))
    #expect(progress?.fraction == 0)
}

@Test func planProgressLastStepInProgressIsNotFullRing() {
    let progress = AgentPlanProgress.fromPlanStatuses(["completed", "completed", "in_progress"])
    #expect(progress == AgentPlanProgress(current: 3, total: 3, completed: 2))
    #expect(progress?.fraction == 2.0 / 3.0)
}

@Test func planProgressUsesTotalWhenAllCompleted() {
    let progress = AgentPlanProgress.fromPlanStatuses(["completed", "completed"])
    #expect(progress == AgentPlanProgress(current: 2, total: 2, completed: 2))
    #expect(progress?.fraction == 1)
}

@Test func planProgressSkipsCompletedWhenNoInProgress() {
    let progress = AgentPlanProgress.fromPlanStatuses(["completed", "pending", "pending"])
    #expect(progress == AgentPlanProgress(current: 2, total: 3, completed: 1))
}

@Test func planProgressRejectsEmptyStatuses() {
    #expect(AgentPlanProgress.fromPlanStatuses([]) == nil)
}

@Test func planProgressIsSupportedByCodexAndDeepSeekOnly() {
    #expect(AgentKind.codex.supportsPlanProgress)
    #expect(AgentKind.deepseek.supportsPlanProgress)
    #expect(AgentKind.cursor.supportsPlanProgress == false)
}
