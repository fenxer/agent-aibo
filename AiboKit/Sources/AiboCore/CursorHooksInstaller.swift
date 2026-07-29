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
        var hooks = (next["hooks"] as? [String: Any]) ?? [:]

        for eventName in cursorEventNames {
            var entries = (hooks[eventName] as? [[String: Any]]) ?? []
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
        guard var hooks = next["hooks"] as? [String: Any] else { return next }

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
