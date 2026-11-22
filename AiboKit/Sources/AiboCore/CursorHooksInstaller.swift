import Foundation

/// Pure dictionary transforms for Cursor's flat `hooks.json` shape.
public enum CursorHooksInstaller {
    public static let commandMarker = "aibo-hook"

    public static let cursorEventNames: [String] = [
        "sessionStart",
        "sessionEnd",
        "beforeSubmitPrompt",
        "preToolUse",
        "postToolUse",
        "postToolUseFailure",
        "beforeShellExecution",
        "afterAgentResponse",
        "subagentStart",
        "subagentStop",
        "stop",
    ]

    public static func isInstalled(_ config: [String: Any]) -> Bool {
        guard let hooks = config["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            if entries.contains(where: isAiboEntry) { return true }
        }
        return false
    }

    public static func install(
        config: [String: Any],
        command: String
    ) throws -> [String: Any] {
        var next = try normalizedRoot(config)
        var hooks = try validatedHooksDictionary(in: next)

        for eventName in cursorEventNames {
            var entries = try validatedEventEntries(in: hooks, key: eventName)
            entries = entries.filter { !isAiboEntry($0) }
            entries.append(aiboEntry(command: command))
            hooks[eventName] = entries
        }

        next["hooks"] = hooks
        if next["version"] == nil {
            next["version"] = 1
        }
        return next
    }

    public static func uninstall(config: [String: Any]) throws -> [String: Any] {
        var next = try normalizedRoot(config)
        guard next["hooks"] != nil, !(next["hooks"] is NSNull) else { return next }
        var hooks = try validatedHooksDictionary(in: next)

        for key in Array(hooks.keys) {
            guard let entries = hooks[key] as? [[String: Any]] else { continue }
            let kept = entries.filter { !isAiboEntry($0) }
            if kept.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = kept
            }
        }

        next["hooks"] = hooks
        return next
    }

    private static func validatedHooksDictionary(in config: [String: Any]) throws -> [String: Any] {
        guard let raw = config["hooks"], !(raw is NSNull) else { return [:] }
        guard let hooks = raw as? [String: Any] else {
            throw HooksInstallerError.invalidHooksShape
        }
        return hooks
    }

    private static func validatedEventEntries(
        in hooks: [String: Any],
        key: String
    ) throws -> [[String: Any]] {
        guard let raw = hooks[key], !(raw is NSNull) else { return [] }
        guard let entries = raw as? [[String: Any]] else {
            throw HooksInstallerError.invalidHooksShape
        }
        return entries
    }

    public static func isAiboEntry(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        return command.contains(commandMarker)
    }

    private static func aiboEntry(command: String) -> [String: Any] {
        [
            "type": "command",
            "command": command,
        ]
    }

    private static func normalizedRoot(_ config: [String: Any]) throws -> [String: Any] {
        // Caller must not pass a non-object parse result; empty is fine.
        if config.isEmpty { return [:] }
        return config
    }

    public static func parseObject(from data: Data) throws -> [String: Any] {
        try HooksConfigJSON.parseObject(from: data)
    }

    public static func encodePretty(_ config: [String: Any]) throws -> Data {
        try HooksConfigJSON.encodePretty(config)
    }
}
