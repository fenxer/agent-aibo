import Foundation

enum HookPayloadFields {
    /// Prefer `workspace_roots[0]`, then `cwd`; return the last path component.
    static func projectName(from payload: [String: Any]) -> String? {
        if let roots = payload["workspace_roots"] as? [String],
           let first = roots.first,
           !first.isEmpty
        {
            return lastPathComponent(first)
        }
        if let cwd = payload["cwd"] as? String, !cwd.isEmpty {
            return lastPathComponent(cwd)
        }
        return nil
    }

    static func modelName(from payload: [String: Any]) -> String? {
        for key in ["model", "model_name", "modelName"] {
            if let value = payload[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// Cursor nests Task/subagent transcripts under `…/subagents/<id>.jsonl`.
    static func isSubagentTranscript(_ path: String?) -> Bool {
        subagentID(fromTranscriptPath: path) != nil
    }

    /// Extracts `<id>` from a path containing `/subagents/<id>` (with or without extension).
    static func subagentID(fromTranscriptPath path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let marker = "/subagents/"
        guard let range = path.range(of: marker) else { return nil }
        let rest = path[range.upperBound...]
        let component = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
        guard let component, !component.isEmpty else { return nil }
        if let dot = component.lastIndex(of: ".") {
            let stem = String(component[..<dot])
            return stem.isEmpty ? nil : stem
        }
        return component
    }

    private static func lastPathComponent(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
