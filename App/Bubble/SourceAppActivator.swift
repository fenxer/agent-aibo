import AiboCore
import AppKit

/// Brings the local agent’s host app to the front (and its Space).
enum SourceAppActivator {
    /// Candidate bundle IDs, preferred first.
    private static func bundleIDs(for agent: AgentKind) -> [String] {
        switch agent {
        case .cursor:
            // Cursor (ToDesktop packaging).
            ["com.todesktop.230313mzl4w4u92"]
        case .codex:
            // Current Codex Desktop; ChatGPT Classic as a fallback.
            ["com.openai.codex", "com.openai.chat"]
        }
    }

    static func activate(_ agent: AgentKind) {
        let ids = bundleIDs(for: agent)
        for id in ids {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                NSApp.yieldActivation(to: app)
                _ = app.activate(from: .current, options: [.activateAllWindows])
                return
            }
        }
        for id in ids {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                continue
            }
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: id)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
    }
}
