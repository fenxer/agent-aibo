import Foundation

/// Markers and event names for the observe-only DeepSeek Harness Cordis plugin.
public enum DeepSeekHarnessPlugin {
    public static let agentMarker = "deepseek"
    public static let pluginID = "aibo-observer"
    public static let beginMarker = "# BEGIN aibo-observer"
    public static let endMarker = "# END aibo-observer"
    public static let bundledDirectoryName = "dsh-aibo"
    public static let pluginMainFileName = "index.js"

    /// Hook names the plugin actually emits (PascalCase, Codex vocabulary).
    public static let eventNames: [String] = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "SubagentStart",
        "SubagentStop",
        "Stop",
    ]
}

public enum DshHomePatchError: Error, Equatable, Sendable {
    case unmatchedMarker
    case unmarkedPluginEntry
}

/// Pure text transforms for `$DSH_HOME/cordis.patch.yml`.
///
/// Only the marked aibo region is inserted or removed. Foreign YAML is kept
/// byte-for-byte. Unreadable marker pairs abort rather than rewrite the file.
public enum DshHomePatch {
    public static func isInstalled(_ existing: String) -> Bool {
        markedRange(in: existing) != nil
    }

    public static func install(existing: String, pluginPath: String) throws -> String {
        try validateMarkers(existing)
        let cleared = try uninstall(existing: existing)
        let block = pluginBlock(pluginPath: pluginPath)
        let trimmed = cleared.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return block + "\n"
        }
        return cleared.trimmingCharacters(in: .newlines) + "\n" + block + "\n"
    }

    public static func uninstall(existing: String) throws -> String {
        try validateMarkers(existing)
        if existing.contains("id: \(DeepSeekHarnessPlugin.pluginID)"),
           markedRange(in: existing) == nil
        {
            throw DshHomePatchError.unmarkedPluginEntry
        }
        guard let range = markedRange(in: existing) else {
            return existing
        }
        var next = existing
        next.removeSubrange(range)
        return next
    }

    private static func markedRange(in existing: String) -> Range<String.Index>? {
        guard let begin = existing.range(of: DeepSeekHarnessPlugin.beginMarker) else {
            if existing.contains(DeepSeekHarnessPlugin.endMarker) {
                return nil
            }
            return nil
        }
        guard let end = existing.range(
            of: DeepSeekHarnessPlugin.endMarker,
            range: begin.upperBound..<existing.endIndex
        ) else {
            return nil
        }
        var start = begin.lowerBound
        if start > existing.startIndex {
            let before = existing.index(before: start)
            if existing[before] == "\n" {
                start = before
            }
        }
        var finish = end.upperBound
        if finish < existing.endIndex, existing[finish] == "\n" {
            finish = existing.index(after: finish)
        }
        return start..<finish
    }

    /// `unmatchedMarker` is reported by install/uninstall callers that see a begin without end.
    public static func validateMarkers(_ existing: String) throws {
        let hasBegin = existing.contains(DeepSeekHarnessPlugin.beginMarker)
        let hasEnd = existing.contains(DeepSeekHarnessPlugin.endMarker)
        if hasBegin != hasEnd {
            throw DshHomePatchError.unmatchedMarker
        }
        if hasBegin, markedRange(in: existing) == nil {
            throw DshHomePatchError.unmatchedMarker
        }
    }

    private static func pluginBlock(pluginPath: String) -> String {
        """
        \(DeepSeekHarnessPlugin.beginMarker)
        - insert:
            - id: \(DeepSeekHarnessPlugin.pluginID)
              name: \(yamlQuoted(pluginPath))
        \(DeepSeekHarnessPlugin.endMarker)
        """
    }

    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
