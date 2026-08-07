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

    /// Compact ingest-log line for Codex `update_plan` (TODO/checklist tool).
    ///
    /// Official shape: `tool_input = { explanation?, plan: [{ step, status }] }` where
    /// `status` is `pending` / `in_progress` / `completed`. Returns nil for other tools.
    static func codexUpdatePlanIngestDetail(
        toolName: String?,
        payload: [String: Any]
    ) -> String? {
        guard let toolName, isUpdatePlanTool(toolName) else { return nil }

        guard let rawInput = payload["tool_input"] ?? payload["toolInput"] else {
            return "update_plan tool_input=missing"
        }

        let inputObject: [String: Any]
        if let dict = rawInput as? [String: Any] {
            inputObject = dict
        } else if let text = rawInput as? String,
                  let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            inputObject = object
        } else {
            return "update_plan tool_input=unparsed"
        }

        var parts: [String] = ["update_plan"]
        if let explanation = inputObject["explanation"] as? String {
            let trimmed = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append("explanation=\(truncate(trimmed, max: 80))")
            }
        }

        guard let plan = inputObject["plan"] as? [[String: Any]], !plan.isEmpty else {
            parts.append("plan=missing")
            return parts.joined(separator: " ")
        }

        let steps = plan.map { item -> String in
            let status = (item["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "?"
            let step = (item["step"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let label = step.isEmpty ? "(empty)" : truncate(step, max: 60)
            return "[\(status)] \(label)"
        }
        parts.append("steps=\(steps.count)")
        parts.append(steps.joined(separator: " | "))
        return parts.joined(separator: " ")
    }

    /// Cursor nests Task/subagent transcripts under `…/subagents/<id>.jsonl`.
    static func isSubagentTranscript(_ path: String?) -> Bool {
        subagentID(fromTranscriptPath: path) != nil
    }

    private static func isUpdatePlanTool(_ toolName: String) -> Bool {
        toolName == "update_plan" || toolName == "UpdatePlan"
    }

    private static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
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
