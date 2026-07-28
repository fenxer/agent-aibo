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

    private static func lastPathComponent(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
