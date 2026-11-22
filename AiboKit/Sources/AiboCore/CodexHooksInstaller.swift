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
        var hooks = try validatedHooksDictionary(in: next)

        for eventName in codexEventNames {
            var groups = try validatedEventGroups(in: hooks, key: eventName)
            groups = groups.compactMap(strippingAiboCommands(from:))
            groups.append(aiboGroup(command: command))
            hooks[eventName] = groups
        }

        next["hooks"] = hooks
        return next
    }

    public static func uninstall(config: [String: Any]) throws -> [String: Any] {
        var next = config
        guard next["hooks"] != nil, !(next["hooks"] is NSNull) else { return next }
        var hooks = try validatedHooksDictionary(in: next)

        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [[String: Any]] else { continue }
            let kept = groups.compactMap(strippingAiboCommands(from:))
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

    /// Removes only aibo entries inside a matcher group, preserving sibling user hooks.
    private static func strippingAiboCommands(from group: [String: Any]) -> [String: Any]? {
        guard let nested = group["hooks"] as? [[String: Any]] else { return group }
        let kept = nested.filter { !isAiboCommandEntry($0) }
        if kept.isEmpty { return nil }
        if kept.count == nested.count { return group }
        var updated = group
        updated["hooks"] = kept
        return updated
    }

    private static func validatedHooksDictionary(in config: [String: Any]) throws -> [String: Any] {
        guard let raw = config["hooks"], !(raw is NSNull) else { return [:] }
        guard let hooks = raw as? [String: Any] else {
            throw HooksInstallerError.invalidHooksShape
        }
        return hooks
    }

    private static func validatedEventGroups(
        in hooks: [String: Any],
        key: String
    ) throws -> [[String: Any]] {
        guard let raw = hooks[key], !(raw is NSNull) else { return [] }
        guard let groups = raw as? [[String: Any]] else {
            throw HooksInstallerError.invalidHooksShape
        }
        return groups
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
