import Foundation

/// Reads hook files and removes one owner's entries.
///
/// Cursor and Windsurf entries are flat. Codex, Claude Code, Gemini CLI, and
/// Qwen wrap each command in a matcher group. Factory's `hooks.json` uses
/// that same group, sometimes at the file root. Antigravity names each hook
/// and nests events inside it. Copilot's macOS command lives in `bash` or
/// `exec`, not only `command`.
///
/// Owners are grouped by the resolved executable, so the same binary
/// registered on several events is one card, while two installs of one app
/// stay separate.
///
/// A removal suggestion is about the app bundle, not the helper inside it:
/// a bundle that is still on disk is an installed app, even if one helper
/// path inside it is broken.
public enum HookInventoryEditor {
    public static func inventory(
        config: [String: Any],
        style: HookFileStyle,
        baseDirectory: URL,
        homeDirectory: URL
    ) -> HookInventory {
        let hooks: [String: Any]
        switch style {
        case .named:
            return namedInventory(
                config: config,
                baseDirectory: baseDirectory,
                homeDirectory: homeDirectory
            )
        case .factory:
            if let wrapped = config["hooks"] as? [String: Any] {
                hooks = wrapped
            } else {
                hooks = config
            }
        case .cursor, .codex:
            guard let wrapped = config["hooks"] as? [String: Any] else {
                let unrecognized = config["hooks"] == nil ? 0 : 1
                return HookInventory(owners: [], unrecognizedCount: unrecognized)
            }
            hooks = wrapped
        }

        var occurrences: [Occurrence] = []
        var unrecognized = 0
        let factoryRoot = style == .factory && (config["hooks"] as? [String: Any]) == nil
        for eventName in orderedEventNames(Array(hooks.keys)) {
            guard let entries = hooks[eventName] as? [Any] else {
                // Factory's unwrapped hooks.json can sit next to a description string.
                if !factoryRoot { unrecognized += 1 }
                continue
            }
            switch style {
            case .cursor:
                unrecognized += collectCursor(
                    entries: entries,
                    eventName: eventName,
                    container: nil,
                    baseDirectory: baseDirectory,
                    homeDirectory: homeDirectory,
                    into: &occurrences
                )
            case .codex, .factory:
                unrecognized += collectCodex(
                    entries: entries,
                    eventName: eventName,
                    container: nil,
                    baseDirectory: baseDirectory,
                    homeDirectory: homeDirectory,
                    into: &occurrences
                )
            case .named:
                break
            }
        }

        return HookInventory(
            owners: owners(from: occurrences),
            unrecognizedCount: unrecognized
        )
    }

    /// Re-reads `config` and drops the owner with this id. Unknown ids leave
    /// the dictionary unchanged, so a stale click cannot rewrite the file.
    public static func removingOwner(
        id: String,
        from config: [String: Any],
        style: HookFileStyle,
        baseDirectory: URL,
        homeDirectory: URL
    ) -> [String: Any] {
        let found = inventory(
            config: config,
            style: style,
            baseDirectory: baseDirectory,
            homeDirectory: homeDirectory
        )
        guard let owner = found.owners.first(where: { $0.id == id }) else {
            return config
        }
        return removing(placements: owner.placements, from: config, style: style)
    }

    private static func removing(
        placements: [HookPlacement],
        from config: [String: Any],
        style: HookFileStyle
    ) -> [String: Any] {
        switch style {
        case .named:
            return removingNamed(placements, from: config)
        case .factory:
            let wrapped = config["hooks"] as? [String: Any]
            let edited = removingEvents(
                placements,
                from: wrapped ?? config,
                nested: true
            )
            if wrapped != nil {
                var next = config
                next["hooks"] = edited
                return next
            }
            return replacingRootEvents(edited, droppedFrom: config)
        case .cursor, .codex:
            guard let hooks = config["hooks"] as? [String: Any] else { return config }
            var next = config
            next["hooks"] = removingEvents(placements, from: hooks, nested: style == .codex)
            return next
        }
    }

    private static func removingEvents(
        _ placements: [HookPlacement],
        from hooks: [String: Any],
        nested: Bool
    ) -> [String: Any] {
        var hooks = hooks
        let byEvent = Dictionary(grouping: placements, by: \.eventName)
        for (eventName, items) in byEvent {
            guard var entries = hooks[eventName] as? [Any] else { continue }
            entries = nested ? removingCodex(items, from: entries) : removingFlat(items, from: entries)
            if entries.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = entries
            }
        }
        return hooks
    }

    private static func removingFlat(_ items: [HookPlacement], from entries: [Any]) -> [Any] {
        let drop = Set(items.map(\.groupIndex))
        return entries.enumerated().compactMap { index, entry in
            drop.contains(index) ? nil : entry
        }
    }

    /// Writes an unwrapped Factory hooks file back without dropping unrelated root keys.
    private static func replacingRootEvents(
        _ edited: [String: Any],
        droppedFrom original: [String: Any]
    ) -> [String: Any] {
        var next = original
        for key in original.keys {
            guard (original[key] as? [Any]) != nil else { continue }
            if let value = edited[key] {
                next[key] = value
            } else {
                next.removeValue(forKey: key)
            }
        }
        return next
    }

    private static func removingNamed(
        _ placements: [HookPlacement],
        from config: [String: Any]
    ) -> [String: Any] {
        var next = config
        let byContainer = Dictionary(grouping: placements, by: { $0.container ?? "" })
        for (container, items) in byContainer {
            guard let definition = next[container] as? [String: Any] else { continue }
            let edited = removingNamedEvents(items, from: definition)
            if edited.values.contains(where: { ($0 as? [Any]) != nil }) {
                next[container] = edited
            } else {
                next.removeValue(forKey: container)
            }
        }
        return next
    }

    private static func removingNamedEvents(
        _ items: [HookPlacement],
        from definition: [String: Any]
    ) -> [String: Any] {
        var definition = definition
        let byEvent = Dictionary(grouping: items, by: \.eventName)
        for (eventName, eventItems) in byEvent {
            guard var entries = definition[eventName] as? [Any] else { continue }
            let byGroup = Dictionary(grouping: eventItems, by: \.groupIndex)
            for groupIndex in byGroup.keys.sorted(by: >) {
                guard entries.indices.contains(groupIndex) else { continue }
                let groupItems = byGroup[groupIndex] ?? []
                if groupItems.contains(where: \.flat) {
                    entries.remove(at: groupIndex)
                    continue
                }
                guard var group = entries[groupIndex] as? [String: Any],
                      var nested = group["hooks"] as? [Any]
                else { continue }
                let drop = Set(groupItems.map(\.commandIndex))
                nested = nested.enumerated().compactMap { index, entry in
                    drop.contains(index) ? nil : entry
                }
                if nested.isEmpty {
                    entries.remove(at: groupIndex)
                } else {
                    group["hooks"] = nested
                    entries[groupIndex] = group
                }
            }
            if entries.isEmpty {
                definition.removeValue(forKey: eventName)
            } else {
                definition[eventName] = entries
            }
        }
        return definition
    }

    /// Group indexes are applied from the end so earlier indexes stay valid.
    private static func removingCodex(_ items: [HookPlacement], from entries: [Any]) -> [Any] {
        var entries = entries
        let byGroup = Dictionary(grouping: items, by: \.groupIndex)
        for groupIndex in byGroup.keys.sorted(by: >) {
            guard entries.indices.contains(groupIndex) else { continue }
            let groupItems = byGroup[groupIndex] ?? []
            if groupItems.contains(where: \.flat) {
                entries.remove(at: groupIndex)
                continue
            }
            guard var group = entries[groupIndex] as? [String: Any],
                  var nested = group["hooks"] as? [Any]
            else { continue }
            let drop = Set(byGroup[groupIndex, default: []].map(\.commandIndex))
            nested = nested.enumerated().compactMap { index, entry in
                drop.contains(index) ? nil : entry
            }
            if nested.isEmpty {
                entries.remove(at: groupIndex)
            } else {
                group["hooks"] = nested
                entries[groupIndex] = group
            }
        }
        return entries
    }

    private static func collectCursor(
        entries: [Any],
        eventName: String,
        container: String?,
        baseDirectory: URL,
        homeDirectory: URL,
        into occurrences: inout [Occurrence]
    ) -> Int {
        var unrecognized = 0
        for (index, entry) in entries.enumerated() {
            guard let object = entry as? [String: Any] else {
                unrecognized += 1
                continue
            }
            if let occurrence = occurrence(
                in: object,
                eventName: eventName,
                groupIndex: index,
                commandIndex: 0,
                groupMatcher: nil,
                container: container,
                flat: true,
                baseDirectory: baseDirectory,
                homeDirectory: homeDirectory
            ) {
                occurrences.append(occurrence)
            } else {
                unrecognized += 1
            }
        }
        return unrecognized
    }

    private static func collectCodex(
        entries: [Any],
        eventName: String,
        container: String?,
        baseDirectory: URL,
        homeDirectory: URL,
        into occurrences: inout [Occurrence]
    ) -> Int {
        var unrecognized = 0
        for (groupIndex, entry) in entries.enumerated() {
            guard let group = entry as? [String: Any] else {
                unrecognized += 1
                continue
            }
            if let nested = group["hooks"] as? [Any] {
                if nested.isEmpty { unrecognized += 1 }
                let groupMatcher = firstNonEmpty(group["matcher"] as? String, group["commandRegex"] as? String)
                for (commandIndex, command) in nested.enumerated() {
                    guard let object = command as? [String: Any] else {
                        unrecognized += 1
                        continue
                    }
                    if let occurrence = occurrence(
                        in: object,
                        eventName: eventName,
                        groupIndex: groupIndex,
                        commandIndex: commandIndex,
                        groupMatcher: groupMatcher,
                        container: container,
                        flat: false,
                        baseDirectory: baseDirectory,
                        homeDirectory: homeDirectory
                    ) {
                        occurrences.append(occurrence)
                    } else {
                        unrecognized += 1
                    }
                }
            } else if let occurrence = occurrence(
                in: group,
                eventName: eventName,
                groupIndex: groupIndex,
                commandIndex: 0,
                groupMatcher: nil,
                container: container,
                flat: true,
                baseDirectory: baseDirectory,
                homeDirectory: homeDirectory
            ) {
                occurrences.append(occurrence)
            } else {
                unrecognized += 1
            }
        }
        return unrecognized
    }

    private static func namedInventory(
        config: [String: Any],
        baseDirectory: URL,
        homeDirectory: URL
    ) -> HookInventory {
        var occurrences: [Occurrence] = []
        var unrecognized = 0
        for name in config.keys.sorted() {
            guard let definition = config[name] as? [String: Any] else { continue }
            for eventName in orderedEventNames(Array(definition.keys)) {
                guard let entries = definition[eventName] as? [Any] else { continue }
                unrecognized += collectCodex(
                    entries: entries,
                    eventName: eventName,
                    container: name,
                    baseDirectory: baseDirectory,
                    homeDirectory: homeDirectory,
                    into: &occurrences
                )
            }
        }
        return HookInventory(owners: owners(from: occurrences), unrecognizedCount: unrecognized)
    }

    private static func occurrence(
        in object: [String: Any],
        eventName: String,
        groupIndex: Int,
        commandIndex: Int,
        groupMatcher: String?,
        container: String?,
        flat: Bool,
        baseDirectory: URL,
        homeDirectory: URL
    ) -> Occurrence? {
        let matcher = firstNonEmpty(object["matcher"] as? String, groupMatcher)
        let placement = HookPlacement(
            eventName: eventName,
            groupIndex: groupIndex,
            commandIndex: commandIndex,
            matcher: matcher,
            container: container,
            flat: flat
        )
        let type = (object["type"] as? String)?.lowercased()
        if type == "http" {
            guard let url = nonEmpty(object["url"] as? String) else { return nil }
            return networkOccurrence(url, placement: placement)
        }
        if type == "mcp_tool" || type == "mcp" {
            guard let server = nonEmpty(object["server"] as? String),
                  let tool = nonEmpty(object["tool"] as? String)
            else { return nil }
            return mcpOccurrence(server: server, tool: tool, placement: placement)
        }
        if type == "prompt" || type == "agent" {
            guard let prompt = nonEmpty(object["prompt"] as? String) else { return nil }
            return promptOccurrence(prompt, placement: placement)
        }
        if let command = resolvedCommand(object) {
            return commandOccurrence(
                command,
                placement: placement,
                baseDirectory: baseDirectory,
                homeDirectory: homeDirectory
            )
        }
        if let prompt = nonEmpty(object["prompt"] as? String) {
            return promptOccurrence(prompt, placement: placement)
        }
        return nil
    }

    /// macOS runs Copilot's `bash` field. Claude's exec form puts the script in `args`.
    private static func resolvedCommand(_ object: [String: Any]) -> String? {
        if let bash = nonEmpty(object["bash"] as? String) { return bash }
        if let command = nonEmpty(object["command"] as? String) {
            return commandLine(executable: command, args: object["args"])
        }
        if let exec = nonEmpty(object["exec"] as? String) {
            return commandLine(executable: exec, args: object["args"])
        }
        if let powershell = nonEmpty(object["powershell"] as? String) { return powershell }
        return nil
    }

    private static func commandLine(executable: String, args: Any?) -> String {
        guard let args = args as? [String], !args.isEmpty else { return executable }
        let rendered = args.map { arg in
            arg.contains(where: \.isWhitespace) ? "\"\(arg)\"" : arg
        }.joined(separator: " ")
        return "\(executable) \(rendered)"
    }

    private static func promptOccurrence(_ prompt: String, placement: HookPlacement) -> Occurrence {
        Occurrence(
            groupID: "prompt:\(prompt)",
            kind: .prompt,
            title: promptTitle(prompt),
            detail: prompt,
            bundlePath: nil,
            resolvedPath: nil,
            placement: placement
        )
    }

    private static func commandOccurrence(
        _ command: String,
        placement: HookPlacement,
        baseDirectory: URL,
        homeDirectory: URL
    ) -> Occurrence? {
        let tokens = HookCommandTokens.all(in: command)
        guard let token = tokens.first else { return nil }
        let target = scriptToken(after: token, in: tokens) ?? token
        let classified = classify(
            token: target,
            baseDirectory: baseDirectory,
            homeDirectory: homeDirectory
        )
        return Occurrence(
            groupID: classified.groupID,
            kind: classified.kind,
            title: classified.title,
            detail: command,
            bundlePath: classified.bundlePath,
            resolvedPath: classified.resolvedPath,
            placement: placement
        )
    }

    private static let interpreters: Set<String> = [
        "node", "nodejs", "python", "python3", "ruby", "perl", "bash", "sh", "zsh", "bun", "deno",
    ]

    /// `node script.js` and `python3 ~/.codex/hooks/check.py` point at the script, not the interpreter.
    private static func scriptToken(after interpreter: String, in tokens: [String]) -> String? {
        guard interpreters.contains(interpreter) else { return nil }
        return tokens.dropFirst().first { token in
            !token.hasPrefix("-") && (token.contains("/") || token.hasPrefix("~") || token.hasPrefix("."))
        }
    }

    private static func networkOccurrence(_ url: String, placement: HookPlacement) -> Occurrence {
        let title = URL(string: url)?.host ?? url
        return Occurrence(
            groupID: "http:\(url)",
            kind: .network,
            title: title,
            detail: url,
            bundlePath: nil,
            resolvedPath: nil,
            placement: placement
        )
    }

    private static func mcpOccurrence(
        server: String,
        tool: String,
        placement: HookPlacement
    ) -> Occurrence {
        Occurrence(
            groupID: "mcp:\(server)/\(tool)",
            kind: .mcpTool,
            title: "\(server) · \(tool)",
            detail: "",
            bundlePath: nil,
            resolvedPath: nil,
            placement: placement
        )
    }

    private static func owners(from occurrences: [Occurrence]) -> [HookOwner] {
        var order: [String] = []
        var grouped: [String: [Occurrence]] = [:]
        for occurrence in occurrences {
            if grouped[occurrence.groupID] == nil {
                order.append(occurrence.groupID)
            }
            grouped[occurrence.groupID, default: []].append(occurrence)
        }

        return order.compactMap { id in
            guard let items = grouped[id], let first = items.first else { return nil }
            var details: [String] = []
            for item in items where !details.contains(item.detail) {
                details.append(item.detail)
            }
            let detail = details.count == 1 ? details[0] : (first.resolvedPath ?? details[0])
            return HookOwner(
                id: id,
                kind: first.kind,
                title: first.title,
                detail: detail == first.title ? "" : detail,
                bundlePath: first.bundlePath,
                resolvedPath: first.resolvedPath,
                placements: items.map(\.placement)
            )
        }
    }

    private static func classify(
        token: String,
        baseDirectory: URL,
        homeDirectory: URL
    ) -> ClassifiedPath {
        let expanded = expandTilde(token, homeDirectory: homeDirectory)
        if expanded.contains("$") {
            let title = expanded.split(separator: "/").last.map(String.init) ?? expanded
            return ClassifiedPath(
                kind: .script,
                title: title,
                bundlePath: nil,
                resolvedPath: nil,
                groupID: "literal:\(expanded)"
            )
        }
        let looksLikePath = expanded.hasPrefix("/") || expanded.hasPrefix(".") || expanded.contains("/")
        guard looksLikePath else {
            return ClassifiedPath(
                kind: .command,
                title: expanded,
                bundlePath: nil,
                resolvedPath: nil,
                groupID: "command:\(expanded)"
            )
        }

        let resolved = resolve(expanded, baseDirectory: baseDirectory, homeDirectory: homeDirectory)
        if let bundlePath = bundlePath(in: resolved) {
            let title = URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
            return ClassifiedPath(
                kind: .application,
                title: title,
                bundlePath: bundlePath,
                resolvedPath: resolved,
                groupID: "path:\(resolved)"
            )
        }

        let title = URL(fileURLWithPath: resolved).lastPathComponent
        return ClassifiedPath(
            kind: expanded.hasPrefix("/") ? .file : .script,
            title: title.isEmpty ? expanded : title,
            bundlePath: nil,
            resolvedPath: resolved,
            groupID: "path:\(resolved)"
        )
    }

    private static func resolve(
        _ path: String,
        baseDirectory: URL,
        homeDirectory: URL
    ) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        let base = URL(fileURLWithPath: baseDirectory.path, isDirectory: true)
        let expandedHome = expandTilde(path, homeDirectory: homeDirectory)
        return URL(fileURLWithPath: expandedHome, relativeTo: base).standardizedFileURL.path
    }

    private static func expandTilde(_ token: String, homeDirectory: URL) -> String {
        if token == "~" { return homeDirectory.path }
        guard token.hasPrefix("~/") else { return token }
        let rest = String(token.dropFirst(2))
        return URL(fileURLWithPath: homeDirectory.path, isDirectory: true)
            .appendingPathComponent(rest)
            .path
    }

    /// First `.app` path component. `My.application` does not count.
    private static func bundlePath(in path: String) -> String? {
        var search = path.startIndex
        while let range = path.range(
            of: ".app",
            options: [.caseInsensitive, .literal],
            range: search..<path.endIndex
        ) {
            let after = range.upperBound
            if after == path.endIndex || path[after] == "/" {
                return String(path[..<after])
            }
            search = after
        }
        return nil
    }

    private static func promptTitle(_ prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(48)) + "…"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private static func firstNonEmpty(_ primary: String?, _ fallback: String?) -> String? {
        if let primary = nonEmpty(primary) {
            return primary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nonEmpty(fallback)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func orderedEventNames(_ names: [String]) -> [String] {
        names.sorted { lhs, rhs in
            let left = eventRank[lhs.lowercased()] ?? Int.max
            let right = eventRank[rhs.lowercased()] ?? Int.max
            if left != right { return left < right }
            return lhs < rhs
        }
    }

    private static let eventRank: [String: Int] = {
        let names = [
            "sessionstart",
            "sessionend",
            "beforesubmitprompt",
            "userpromptsubmit",
            "pretooluse",
            "posttooluse",
            "posttoolusefailure",
            "beforeshellexecution",
            "aftershellexecution",
            "beforemcpexecution",
            "aftermcpexecution",
            "beforereadfile",
            "afterfileedit",
            "afteragentresponse",
            "afteragentthought",
            "subagentstart",
            "subagentstop",
            "stop",
            "permissionrequest",
            "precompact",
            "beforetabfileread",
            "aftertabfileedit",
        ]
        return Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
    }()
}

public enum HookFileStyle: Equatable, Sendable {
    /// Flat `{ "hooks": { "event": [ { "command": "…" } ] } }`. Cursor, Windsurf, Copilot.
    case cursor
    /// `{ "hooks": { "Event": [ { "hooks": [ { "command": "…" } ] } ] } }`.
    /// Codex, Claude Code, Gemini CLI, and Qwen Code.
    case codex
    /// Factory `hooks.json`: the same groups, either under `hooks` or at the file root.
    case factory
    /// Antigravity: each top-level name owns its own event map.
    case named
}

public enum HookOwnerKind: Equatable, Sendable {
    case application
    case file
    case script
    case command
    case prompt
    case network
    case mcpTool
}

public struct HookInventory: Equatable, Sendable {
    public static let empty = HookInventory(owners: [], unrecognizedCount: 0)

    public let owners: [HookOwner]
    public let unrecognizedCount: Int
}

public struct HookOwner: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: HookOwnerKind
    public let title: String
    public let detail: String
    public let bundlePath: String?
    public let resolvedPath: String?
    public let placements: [HookPlacement]

    public func suggestsRemoval(fileExists: (String) -> Bool) -> Bool {
        switch kind {
        case .application:
            guard let bundlePath else { return false }
            return !fileExists(bundlePath)
        case .file, .script:
            guard let resolvedPath else { return false }
            return !fileExists(resolvedPath)
        case .command, .prompt, .network, .mcpTool:
            return false
        }
    }
}

public struct HookPlacement: Equatable, Hashable, Sendable {
    public let eventName: String
    public let groupIndex: Int
    public let commandIndex: Int
    public let matcher: String?
    /// Antigravity hook name. Nil for the other file shapes.
    public let container: String?
    /// The command is the event entry itself, not an item inside a nested `hooks` array.
    public let flat: Bool
}

private struct Occurrence {
    var groupID: String
    var kind: HookOwnerKind
    var title: String
    var detail: String
    var bundlePath: String?
    var resolvedPath: String?
    var placement: HookPlacement
}

private struct ClassifiedPath {
    var kind: HookOwnerKind
    var title: String
    var bundlePath: String?
    var resolvedPath: String?
    var groupID: String
}

/// Shell tokens, including quoted paths and backslash-escaped spaces.
private enum HookCommandTokens {
    static func first(in command: String) -> String? {
        all(in: command).first
    }

    static func all(in command: String) -> [String] {
        var index = command.startIndex
        var tokens: [String] = []
        while index < command.endIndex {
            while index < command.endIndex, command[index].isWhitespace {
                index = command.index(after: index)
            }
            guard index < command.endIndex else { break }
            let quote = command[index]
            if quote == "\"" || quote == "'" {
                index = command.index(after: index)
                var token = ""
                while index < command.endIndex {
                    let character = command[index]
                    index = command.index(after: index)
                    if character == quote { break }
                    if character == "\\", quote == "\"", index < command.endIndex {
                        token.append(command[index])
                        index = command.index(after: index)
                        continue
                    }
                    token.append(character)
                }
                if !token.isEmpty { tokens.append(token) }
                continue
            }
            var token = ""
            while index < command.endIndex, !command[index].isWhitespace {
                let character = command[index]
                index = command.index(after: index)
                if character == "\\" {
                    if index < command.endIndex {
                        token.append(command[index])
                        index = command.index(after: index)
                    }
                    continue
                }
                token.append(character)
            }
            if !token.isEmpty { tokens.append(token) }
        }
        return tokens
    }
}
