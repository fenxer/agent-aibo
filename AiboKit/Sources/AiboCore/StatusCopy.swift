import Foundation

/// Local templates for agent status. Never call an LLM from this path.
public enum StatusCopy {
    /// Full sentence used by non-bubble callers (e.g. LLM helpers).
    public static func message(
        for activity: AiboActivityState,
        agent: AgentKind
    ) -> String? {
        guard let phrase = statusPhrase(for: activity) else { return nil }
        return "\(displayName(agent)) \(phrase)"
    }

    /// Status text shown beside the agent capsule (no agent name prefix).
    ///
    /// `waitingToolName` is unused for Codex live copy (see `requestPermissionPhrase`).
    /// DeepSeek keeps the generic “is reviewing” phrase and may still escalate later.
    public static func statusPhrase(
        for activity: AiboActivityState,
        waitingToolName: String? = nil
    ) -> String? {
        switch activity {
        case .idle:
            return nil
        case .registered:
            return "session started"
        case .thinking:
            return "is thinking"
        case let .usingTool(name):
            return "is using \(name)"
        case .responding:
            return "is responding"
        case .waiting:
            let trimmed = waitingToolName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return "is reviewing \(trimmed)"
            }
            return "is reviewing"
        case .done:
            return "finished"
        case .interrupted:
            return "was interrupted"
        case .failed:
            return "failed"
        }
    }

    /// Codex `.waiting` (PermissionRequest / `request_permissions`). Verb, not “is using”.
    public static let requestPermissionPhrase = "request permission"

    /// Escalated `.waiting` copy after silence (see `WaitingApprovalEscalationHint`).
    ///
    /// DeepSeek still shares a generic `PermissionRequest`. Codex shows
    /// `requestPermissionPhrase` plus the arrow instead of escalating.
    public static let needsYourApprovalPhrase = stuckPhrase

    /// Attention CTA after silence (Cursor `.usingTool` stall, or escalated `.waiting`).
    public static let stuckPhrase = "got stuck?"

    /// Codex plan-mode / `update_plan` while still in `.thinking`.
    public static let planningPhrase = "is planning"

    /// Bubble-style example under a hook name in Settings → Sprite Actions.
    ///
    /// Uses the same phrases as live bubbles (`statusPhrase`), with sample tool names.
    public static func exampleBubblePhrase(
        agent: AgentKind,
        hookEventName: String
    ) -> String? {
        // Cursor `stop` maps to done / interrupted / failed depending on status.
        if agent == .cursor, hookEventName == "stop" {
            return "finished · was interrupted · failed"
        }

        let transition: StateTransition?
        switch agent {
        case .cursor:
            transition = CursorEventMapper.transition(
                eventName: hookEventName,
                toolName: "Shell",
                stopStatus: "completed"
            )
        case .codex, .deepseek:
            transition = CodexEventMapper.transition(
                eventName: hookEventName,
                toolName: "Bash"
            )
        }

        switch transition {
        case .apply(let activity):
            if activity == .waiting, agent == .codex {
                return requestPermissionPhrase
            }
            guard let phrase = statusPhrase(for: activity) else { return nil }
            if activity == .waiting {
                return "\(phrase) · \(stuckPhrase)"
            }
            return phrase
        case .removeSession:
            return "clears session"
        case nil:
            return nil
        }
    }

    /// Natural-language subtitle under a hook name in Agent Hook settings.
    public static func hookSettingDescription(
        agent: AgentKind,
        hookEventName: String
    ) -> String? {
        switch agent {
        case .cursor:
            switch hookEventName {
            case "sessionStart":
                return "Start a new conversation" // 发起新对话
            case "sessionEnd":
                return "Conversation ended" // 对话结束
            case "beforeSubmitPrompt":
                return "Submitted prompt and started thinking" // 提交了提示词，开始思考
            case "preToolUse":
                return "About to use a tool (e.g. is using Shell)" // 即将调用工具。比如 is using Shell
            case "postToolUse":
                return "Tool finished; still thinking" // 工具跑完，继续思考
            case "postToolUseFailure":
                return "Tool failed; still thinking" // 工具失败后继续思考
            case "beforeShellExecution":
                return "About to run a terminal command" // 即将执行终端命令
            case "afterAgentResponse":
                return "Writing reply" // 正在写出回复
            case "subagentStart":
                return "Subagent started" // 子任务开始
            case "subagentStop":
                return "Subagent ended" // 子任务结束
            case "stop":
                return "Turn ended" // 本轮对话结束
            default:
                return nil
            }
        case .codex, .deepseek:
            switch hookEventName {
            case "SessionStart":
                return "Start a new conversation" // 发起新对话
            case "SessionEnd":
                return "Conversation ended" // 对话结束
            case "UserPromptSubmit":
                return "Submitted prompt and started thinking (e.g. is planning in plan mode)" // 提交了提示词，开始思考。比如计划模式时是 is planning
            case "PreToolUse":
                return "About to use a tool (e.g. is using Bash)" // 即将调用工具。比如 is using Bash
            case "PostToolUse":
                return "Tool finished; still thinking" // 工具跑完，继续思考
            case "PermissionRequest":
                if agent == .codex {
                    return "Waiting on a permission prompt (e.g. request permission)" // 等待权限确认。比如 request permission
                }
                return "Waiting for approval or auto-review (e.g. is reviewing, then got stuck?)" // 等待审批或自动审查。比如 is reviewing，沉默几秒后变成 got stuck?
            case "SubagentStart":
                return "Subagent started" // 子任务开始
            case "SubagentStop":
                return "Subagent ended" // 子任务结束
            case "Stop":
                return "Turn ended" // 本轮对话结束
            default:
                return nil
            }
        }
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .deepseek: "DeepSeek Harness"
        }
    }

    /// Name printed on the bubble capsule. Settings still spell the agent out;
    /// the capsule is width-constrained, so a long name steals room from the status.
    public static func capsuleName(_ agent: AgentKind) -> String {
        switch agent {
        case .cursor, .codex: displayName(agent)
        case .deepseek: "DSH"
        }
    }
}
