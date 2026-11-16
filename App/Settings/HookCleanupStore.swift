import AiboCore
import Foundation

/// User-level hook files for the agents that publish a JSON hook config.
/// Project files are left alone. A file that cannot be parsed is not written.
enum HookCleanupStore {
    struct File: Identifiable {
        var id: String
        var agentName: String
        var heading: String
        var style: HookFileStyle
        var url: URL
        var inventory: HookInventory
        var issue: Issue?
    }

    enum Issue {
        case missing
        case unreadable
    }

    enum WriteError: Error {
        case invalidFile
        case failed
    }

    static func load() -> [File] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return sources(home: home).map { source in
            load(source, home: home)
        }
    }

    static func remove(ownerID: String, from file: File) throws {
        let data: Data
        do {
            data = try Data(contentsOf: file.url)
        } catch {
            throw WriteError.failed
        }

        let config: [String: Any]
        do {
            config = try HooksConfigJSON.parseObject(from: data)
        } catch {
            throw WriteError.invalidFile
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = file.url.deletingLastPathComponent()
        let current = HookInventoryEditor.inventory(
            config: config,
            style: file.style,
            baseDirectory: base,
            homeDirectory: home
        )
        guard current.owners.contains(where: { $0.id == ownerID }) else { return }

        let next = HookInventoryEditor.removingOwner(
            id: ownerID,
            from: config,
            style: file.style,
            baseDirectory: base,
            homeDirectory: home
        )
        do {
            let encoded = try HooksConfigJSON.encodePretty(next)
            try encoded.write(to: file.url, options: .atomic)
        } catch {
            throw WriteError.failed
        }
    }

    private struct Source {
        var id: String
        var agentName: String
        var heading: String
        var style: HookFileStyle
        var url: URL
    }

    private static func sources(home: URL) -> [Source] {
        var sources = [
            source("cursor", "Cursor", ".cursor/hooks.json", .cursor, home: home),
            source("codex", "Codex", ".codex/hooks.json", .codex, home: home),
            source("claude", "Claude Code", ".claude/settings.json", .codex, home: home),
            source("gemini", "Gemini CLI", ".gemini/settings.json", .codex, home: home),
            source("qwen", "Qwen Code", ".qwen/settings.json", .codex, home: home),
            source("windsurf", "Windsurf", ".codeium/windsurf/hooks.json", .cursor, home: home),
            source("antigravity", "Antigravity", ".gemini/config/hooks.json", .named, home: home),
        ]
        sources.append(factorySource(home: home))
        sources.append(contentsOf: copilotSources(home: home))
        return sources
    }

    /// Factory reads `hooks.json` first, then the legacy nested path, then `settings.json`.
    private static func factorySource(home: URL) -> Source {
        let hooks = home.appending(path: ".factory/hooks.json")
        let legacy = home.appending(path: ".factory/hooks/hooks.json")
        let settings = home.appending(path: ".factory/settings.json")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: hooks.path) {
            return factory("factory", url: hooks, style: .factory)
        }
        if fileManager.fileExists(atPath: legacy.path) {
            return factory("factory-legacy", url: legacy, style: .factory)
        }
        if fileManager.fileExists(atPath: settings.path) {
            return factory("factory-settings", url: settings, style: .codex)
        }
        return factory("factory", url: hooks, style: .factory)
    }

    private static func factory(_ id: String, url: URL, style: HookFileStyle) -> Source {
        Source(id: id, agentName: "Factory Droid", heading: "Factory Droid", style: style, url: url)
    }

    /// Copilot keeps one hooks object in settings and more JSON files in `hooks/`.
    private static func copilotSources(home: URL) -> [Source] {
        let settings = home.appending(path: ".copilot/settings.json")
        let directory = home.appending(path: ".copilot/hooks", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let hookFiles = names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .sorted()
        var sources: [Source] = []
        if FileManager.default.fileExists(atPath: settings.path) {
            sources.append(
                Source(
                    id: "copilot-settings",
                    agentName: "GitHub Copilot",
                    heading: "GitHub Copilot",
                    style: .cursor,
                    url: settings
                )
            )
        }
        for name in hookFiles {
            sources.append(
                Source(
                    id: "copilot-\(name)",
                    agentName: "GitHub Copilot",
                    heading: "GitHub Copilot · \(name)",
                    style: .cursor,
                    url: directory.appending(path: name)
                )
            )
        }
        if sources.isEmpty {
            sources.append(
                Source(
                    id: "copilot",
                    agentName: "GitHub Copilot",
                    heading: "GitHub Copilot",
                    style: .cursor,
                    url: settings
                )
            )
        }
        return sources
    }

    private static func source(
        _ id: String,
        _ agentName: String,
        _ path: String,
        _ style: HookFileStyle,
        home: URL
    ) -> Source {
        Source(
            id: id,
            agentName: agentName,
            heading: agentName,
            style: style,
            url: home.appending(path: path)
        )
    }

    private static func load(_ source: Source, home: URL) -> File {
        let empty = HookInventory.empty
        guard FileManager.default.fileExists(atPath: source.url.path) else {
            return File(
                id: source.id,
                agentName: source.agentName,
                heading: source.heading,
                style: source.style,
                url: source.url,
                inventory: empty,
                issue: .missing
            )
        }
        do {
            let data = try Data(contentsOf: source.url)
            let config = try HooksConfigJSON.parseObject(from: data)
            let inventory = HookInventoryEditor.inventory(
                config: config,
                style: source.style,
                baseDirectory: source.url.deletingLastPathComponent(),
                homeDirectory: home
            )
            return File(
                id: source.id,
                agentName: source.agentName,
                heading: source.heading,
                style: source.style,
                url: source.url,
                inventory: inventory,
                issue: nil
            )
        } catch {
            return File(
                id: source.id,
                agentName: source.agentName,
                heading: source.heading,
                style: source.style,
                url: source.url,
                inventory: empty,
                issue: .unreadable
            )
        }
    }
}
