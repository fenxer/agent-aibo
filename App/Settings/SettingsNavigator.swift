import AppKit
import Foundation
import SwiftUI

/// Deep-links into the Settings scene sidebar (Integrations, etc.).
///
/// Opening Settings must go through `SettingsLink` (calling `openSettings()` warns
/// on current SDKs). Callers set `pendingPane` then rely on a `SettingsLink` tap.
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

    private var didPromoteActivationPolicy = false
    private var settingsCloseObserver: NSObjectProtocol?

    /// Prepare Integrations selection before a `SettingsLink` opens the scene.
    func prepareIntegrations() {
        pendingPane = .integrations
        promoteActivationPolicyForSettingsIfNeeded()
    }

    func consumePendingPane() -> Pane? {
        let pane = pendingPane
        pendingPane = nil
        return pane
    }

    /// Accessory apps often need a brief `.regular` policy so Settings can key.
    func promoteActivationPolicyForSettingsIfNeeded() {
        guard NSApp.activationPolicy() == .accessory else { return }
        NSApp.setActivationPolicy(.regular)
        didPromoteActivationPolicy = true
        NSApp.activate(ignoringOtherApps: true)
        watchSettingsWindowForAccessoryRestore()
    }

    private func watchSettingsWindowForAccessoryRestore() {
        if let settingsCloseObserver {
            NotificationCenter.default.removeObserver(settingsCloseObserver)
            self.settingsCloseObserver = nil
        }
        guard didPromoteActivationPolicy else { return }

        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                guard let self else { return }
                guard self.isLikelySettingsWindow(window) else { return }
                self.restoreAccessoryPolicyIfNeeded()
            }
        }
    }

    private func isLikelySettingsWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible || window.isMiniaturized else { return false }
        guard !(window is NSPanel) else { return false }
        let contentWidth = window.contentRect(forFrameRect: window.frame).width
        return abs(contentWidth - AppSettings.settingsWindowWidth) < 2
    }

    private func restoreAccessoryPolicyIfNeeded() {
        guard didPromoteActivationPolicy else { return }
        let settingsStillOpen = NSApp.windows.contains {
            $0.isVisible && self.isLikelySettingsWindow($0)
        }
        guard !settingsStillOpen else { return }
        didPromoteActivationPolicy = false
        if let settingsCloseObserver {
            NotificationCenter.default.removeObserver(settingsCloseObserver)
            self.settingsCloseObserver = nil
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
