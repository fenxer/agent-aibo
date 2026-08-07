import AppKit
import Foundation

/// Deep-links into the Settings scene sidebar (Integrations, etc.).
///
/// Opening Settings must go through `SettingsLink` (calling `openSettings()` /
/// `showSettingsWindow:` warns and often no-ops on current SDKs). Call
/// `prepareForOpeningSettings()` alongside the link so the accessory app can
/// activate and the Settings window can become key — without promoting to
/// `.regular` (that would show a Dock icon).
@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()

    enum Pane: String, Equatable {
        case appearance
        case integrations
        case receiveLog
        case about
        #if DEBUG
        case development
        #endif
    }

    /// Consumed by `SettingsView` when the window appears or this value changes.
    private(set) var pendingPane: Pane?

    private var bringToFrontTask: Task<Void, Never>?

    /// Prepare Integrations selection before a `SettingsLink` opens the scene.
    func prepareIntegrations() {
        pendingPane = .integrations
        prepareForOpeningSettings()
    }

    /// Call alongside `SettingsLink` (menu, warning bubble, etc.) so accessory apps can key.
    func prepareForOpeningSettings() {
        activateForSettings()
        scheduleBringSettingsWindowToFront()
    }

    func consumePendingPane() -> Pane? {
        let pane = pendingPane
        pendingPane = nil
        return pane
    }

    /// Stay `.accessory` (no Dock). Activate so Settings can become key.
    /// Only invoked from explicit user "open Settings" paths — never on wake/probes.
    func activateForSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Settings content attached — ensure we are frontmost (first attach / reopen).
    func handleSettingsWindowAppeared(_ window: NSWindow) {
        activateForSettings()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func scheduleBringSettingsWindowToFront() {
        bringToFrontTask?.cancel()
        bringToFrontTask = Task { @MainActor in
            // Settings scene creation is async after the menu action returns.
            for delay in [Duration.milliseconds(50), .milliseconds(150), .milliseconds(350)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                if bringSettingsWindowToFrontIfPossible() {
                    return
                }
            }
        }
    }

    @discardableResult
    private func bringSettingsWindowToFrontIfPossible() -> Bool {
        guard let window = findSettingsWindow() else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func findSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard !(window is NSPanel) else { return false }
            let contentWidth = window.contentRect(forFrameRect: window.frame).width
            return abs(contentWidth - AppSettings.settingsWindowWidth) < 2
        }
    }
}
