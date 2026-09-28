import Foundation

/// Per-agent overrides of which Petdex atlas row a hook event drives.
public struct HookSpriteMappingFile: Codable, Sendable, Equatable {
    /// Cursor hook event name → `PetdexSpriteState.rawValue`.
    public var cursor: [String: String]
    /// Codex hook event name → `PetdexSpriteState.rawValue`.
    public var codex: [String: String]
    /// DeepSeek Harness hook event name → `PetdexSpriteState.rawValue`.
    public var deepseek: [String: String]

    public init(
        cursor: [String: String] = [:],
        codex: [String: String] = [:],
        deepseek: [String: String] = [:]
    ) {
        self.cursor = cursor
        self.codex = codex
        self.deepseek = deepseek
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent([String: String].self, forKey: .cursor) ?? [:]
        codex = try container.decodeIfPresent([String: String].self, forKey: .codex) ?? [:]
        deepseek = try container.decodeIfPresent([String: String].self, forKey: .deepseek) ?? [:]
    }
}

public enum HookSpriteMapping {
    /// Hooks shown in Agent Hook advanced settings / used for sprite lookup (installed set).
    public static func configurableHooks(for agent: AgentKind) -> [String] {
        switch agent {
        case .cursor:
            return CursorHooksInstaller.cursorEventNames
        case .codex:
            return CodexHooksInstaller.codexEventNames
        case .deepseek:
            return DeepSeekHarnessPlugin.eventNames
        }
    }

    public static func defaultSprite(agent: AgentKind, hookEventName: String) -> PetdexSpriteState {
        switch agent {
        case .cursor:
            return defaultCursorSprite(hookEventName)
        case .codex, .deepseek:
            return defaultCodexSprite(hookEventName)
        }
    }

    public static func resolve(
        agent: AgentKind,
        hookEventName: String?,
        activity: AiboActivityState,
        overrides: HookSpriteMappingFile
    ) -> PetdexSpriteState {
        if activity == .idle {
            return .idle
        }
        // Blocked on the user's answer. Don't inherit the PreToolUse "running" pose.
        if activity.waitsForUserReply {
            return .waiting
        }
        let lookupEvent = spriteEventName(
            agent: agent,
            hookEventName: hookEventName,
            activity: activity
        )
        if let lookupEvent,
           let raw = overrideRaw(agent: agent, hookEventName: lookupEvent, file: overrides),
           let sprite = PetdexSpriteState(rawValue: raw)
        {
            return sprite
        }
        if let lookupEvent {
            if agent == .cursor, lookupEvent == "stop" {
                switch activity {
                case .failed: return .failed
                case .interrupted: return .waving
                default: return .waving
                }
            }
            return defaultSprite(agent: agent, hookEventName: lookupEvent)
        }
        return PetdexSpriteStateMapper.state(for: activity)
    }

    /// Auto-approved Codex `PermissionRequest` is a normal command (`.usingTool`).
    /// Use the `PreToolUse` pose so the pet does not sit in the approval wait.
    private static func spriteEventName(
        agent: AgentKind,
        hookEventName: String?,
        activity: AiboActivityState
    ) -> String? {
        guard let hookEventName else { return nil }
        guard agent == .codex, hookEventName == "PermissionRequest" else { return hookEventName }
        if case .usingTool = activity {
            return "PreToolUse"
        }
        return hookEventName
    }

    public static func effectiveSprite(
        agent: AgentKind,
        hookEventName: String,
        overrides: HookSpriteMappingFile
    ) -> PetdexSpriteState {
        if let raw = overrideRaw(agent: agent, hookEventName: hookEventName, file: overrides),
           let sprite = PetdexSpriteState(rawValue: raw)
        {
            return sprite
        }
        return defaultSprite(agent: agent, hookEventName: hookEventName)
    }

    private static func overrideRaw(
        agent: AgentKind,
        hookEventName: String,
        file: HookSpriteMappingFile
    ) -> String? {
        switch agent {
        case .cursor: file.cursor[hookEventName]
        case .codex: file.codex[hookEventName]
        case .deepseek: file.deepseek[hookEventName]
        }
    }

    private static func defaultCursorSprite(_ hook: String) -> PetdexSpriteState {
        switch hook {
        case "sessionStart", "beforeSubmitPrompt", "postToolUse", "postToolUseFailure",
             "afterAgentResponse", "subagentStart":
            return .jumping
        case "preToolUse", "beforeShellExecution":
            return .running
        case "stop", "subagentStop":
            return .waving
        case "sessionEnd":
            return .idle
        default:
            return .jumping
        }
    }

    private static func defaultCodexSprite(_ hook: String) -> PetdexSpriteState {
        switch hook {
        case "SessionStart", "UserPromptSubmit", "PostToolUse", "SubagentStart":
            return .jumping
        case "PreToolUse":
            return .running
        case "PermissionRequest":
            return .waiting
        case "Stop", "SubagentStop":
            return .waving
        case "SessionEnd":
            return .idle
        default:
            return .jumping
        }
    }
}

extension PetdexSpriteState {
    public var displayName: String {
        switch self {
        case .idle: "Idle"
        case .runningRight: "Run Right"
        case .runningLeft: "Run Left"
        case .waving: "Waving"
        case .jumping: "Jumping"
        case .failed: "Failed"
        case .waiting: "Waiting"
        case .running: "Running"
        case .review: "Review"
        }
    }
}
