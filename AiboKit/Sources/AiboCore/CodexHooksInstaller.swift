import Foundation

/// Pure dictionary transforms for Codex's nested `hooks.json` shape.
///
/// ```json
/// { "hooks": { "PreToolUse": [ { "hooks": [ { "type": "command", "command": "…" } ] } ] } }
/// ```
public enum CodexHooksInstaller {
    public static let commandMarker = "aibo-hook"

    public static let codexEventNames: [String] = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "SubagentStart",
        "SubagentStop",
        "Stop",
    ]

    public static func isInstalled(_ config: [String: Any]) -> Bool {
        guard let hooks = config["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            if groups.contains(where: isAiboGroup) { return true }
        }
        return false
    }

    public static func install(
        config: [String: Any],
        command: String
    ) throws -> [String: Any] {
        var next = config
        var hooks = (next["hooks"] as? [String: Any]) ?? [:]

        for eventName in codexEventNames {
            var groups = (hooks[eventName] as? [[String: Any]]) ?? []
            groups = groups.filter { !isAiboGroup($0) }
            groups.append(aiboGroup(command: command))
            hooks[eventName] = groups
        }

        next["hooks"] = hooks
        return next
    }

    public static func uninstall(config: [String: Any]) throws -> [String: Any] {
        var next = config
        guard var hooks = next["hooks"] as? [String: Any] else { return next }

        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [[String: Any]] else { continue }
            let kept = groups.filter { !isAiboGroup($0) }
            if kept.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = kept
            }
        }

        next["hooks"] = hooks
        return next
    }

    public static func isAiboGroup(_ group: [String: Any]) -> Bool {
        guard let nested = group["hooks"] as? [[String: Any]] else { return false }
        return nested.contains(where: isAiboCommandEntry)
    }

    public static func isAiboCommandEntry(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        return command.contains(commandMarker)
    }

    private static func aiboGroup(command: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                ],
            ],
        ]
    }
}
