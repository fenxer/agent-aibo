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
            // ChatGPT Desktop now ships as `com.openai.codex` (Info shows ChatGPT.app).
            // Keep Classic as a fallback for older installs.
            ["com.openai.codex", "com.openai.chat"]
        }
    }

    static func activate(_ agent: AgentKind) {
        let ids = bundleIDs(for: agent)
        if let app = preferredRunningApp(bundleIDs: ids) {
            if activateRunning(app) { return }
        }
        openInstalledApp(bundleIDs: ids)
    }

    /// Prefer a regular, non-finished instance; among ties, the most recently launched.
    private static func preferredRunningApp(bundleIDs: [String]) -> NSRunningApplication? {
        var candidates: [NSRunningApplication] = []
        for id in bundleIDs {
            candidates.append(
                contentsOf: NSRunningApplication.runningApplications(withBundleIdentifier: id)
            )
        }
        let usable = candidates.filter { !$0.isTerminated }
        guard !usable.isEmpty else { return nil }

        let ranked = usable.sorted { lhs, rhs in
            if lhs.activationPolicy != rhs.activationPolicy {
                return rank(lhs.activationPolicy) < rank(rhs.activationPolicy)
            }
            let leftLaunch = lhs.launchDate ?? .distantPast
            let rightLaunch = rhs.launchDate ?? .distantPast
            return leftLaunch > rightLaunch
        }
        return ranked.first
    }

    private static func rank(_ policy: NSApplication.ActivationPolicy) -> Int {
        switch policy {
        case .regular: 0
        case .accessory: 1
        case .prohibited: 2
        @unknown default: 3
        }
    }

    /// Cooperative yield + activate; returns whether activation was accepted.
    @discardableResult
    private static func activateRunning(_ app: NSRunningApplication) -> Bool {
        NSApp.yieldActivation(to: app)
        if app.activate(from: .current, options: [.activateAllWindows]) {
            return true
        }
        // Electron hosts (ChatGPT Desktop) sometimes reject the first cooperative
        // request; opening the bundle again is a reliable “come to front” nudge.
        guard let url = app.bundleURL else { return false }
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: app.bundleIdentifier ?? "")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    private static func openInstalledApp(bundleIDs: [String]) {
        for id in bundleIDs {
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
