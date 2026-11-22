import Foundation

/// Pure dictionary transforms for Antigravity's named `hooks.json`.
///
/// Each top-level name owns its events. Tool events nest `{ matcher, hooks }`.
/// Session and model events are a flat list of commands. Copying the nested
/// shape onto those events makes Antigravity drop the hook.
///
/// ```json
/// {
///   "aibo": {
///     "PreToolUse": [{ "matcher": "*", "hooks": [{ "command": "…" }] }],
///     "SessionStart": [{ "command": "…" }]
///   }
/// }
/// ```
public enum AntigravityHooksInstaller {
    public static let commandMarker = "aibo-hook"
    public static let agentArgument = "antigravity"
    public static let hookName = "aibo"
    /// Seconds. The helper only writes a socket line; this caps a hang.
    public static let timeoutSeconds = 10

    public static let eventNames: [String] = [
        "SessionStart",
        "PreInvocation",
        "PreToolUse",
        "PostToolUse",
        "Stop",
    ]

    private static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    /// Shell command Antigravity spawns. The event name is an argument because
    /// the stdin payload does not say which event fired.
    public static func shellCommand(binaryPath: String, eventName: String) -> String {
        "\(quote(binaryPath)) \(agentArgument) \(eventName)"
    }

    public static func isInstalled(_ config: [String: Any]) -> Bool {
        commands(in: config).contains(where: isAiboCommand)
    }

    public static func install(
        config: [String: Any],
        binaryPath: String
    ) -> [String: Any] {
        var next = uninstall(config: config)
        var container = (next[hookName] as? [String: Any]) ?? [:]
        container.removeValue(forKey: "enabled")
        for eventName in eventNames {
            var entries = (container[eventName] as? [[String: Any]]) ?? []
            entries.append(handler(for: eventName, binaryPath: binaryPath))
            container[eventName] = entries
        }
        next[hookName] = container
        return next
    }

    public static func uninstall(config: [String: Any]) -> [String: Any] {
        var next = config
        for name in Array(next.keys) {
            guard let container = next[name] as? [String: Any] else { continue }
            if let kept = strippingAiboCommands(from: container) {
                next[name] = kept
            } else {
                next.removeValue(forKey: name)
            }
        }
        return next
    }

    public static func isAiboCommand(_ command: String) -> Bool {
        command.contains(commandMarker) && command.contains(" \(agentArgument) ")
    }

    private static func handler(for eventName: String, binaryPath: String) -> [String: Any] {
        let command: [String: Any] = [
            "type": "command",
            "command": shellCommand(binaryPath: binaryPath, eventName: eventName),
            "timeout": timeoutSeconds,
        ]
        if toolEvents.contains(eventName) {
            return [
                "matcher": "*",
                "hooks": [command],
            ]
        }
        return command
    }

    private static func strippingAiboCommands(from container: [String: Any]) -> [String: Any]? {
        var next = container
        for key in Array(next.keys) {
            guard let entries = next[key] as? [[String: Any]] else { continue }
            let kept = entries.compactMap { stripEntry($0) }
            if kept.isEmpty {
                next.removeValue(forKey: key)
            } else {
                next[key] = kept
            }
        }
        let hasEvents = next.values.contains { $0 is [[String: Any]] }
        return hasEvents ? next : nil
    }

    /// Flat command entries drop themselves. Matcher groups drop our commands
    /// and disappear when none remain.
    private static func stripEntry(_ entry: [String: Any]) -> [String: Any]? {
        if let hooks = entry["hooks"] as? [[String: Any]] {
            let kept = hooks.filter { commandText($0).map(isAiboCommand) != true }
            if kept.isEmpty { return nil }
            var next = entry
            next["hooks"] = kept
            return next
        }
        if let command = commandText(entry), isAiboCommand(command) {
            return nil
        }
        return entry
    }

    private static func commands(in config: [String: Any]) -> [String] {
        var found: [String] = []
        for value in config.values {
            guard let container = value as? [String: Any] else { continue }
            for event in container.values {
                guard let entries = event as? [[String: Any]] else { continue }
                for entry in entries {
                    if let hooks = entry["hooks"] as? [[String: Any]] {
                        found.append(contentsOf: hooks.compactMap(commandText))
                    } else if let command = commandText(entry) {
                        found.append(command)
                    }
                }
            }
        }
        return found
    }

    private static func commandText(_ entry: [String: Any]) -> String? {
        entry["command"] as? String
    }

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
