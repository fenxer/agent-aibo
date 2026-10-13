import Foundation

/// Deep-links into Settings (Webhook, an extension, …) and presents the window.
///
/// The window is `SettingsWindowController`'s `NSWindow`, not a SwiftUI
/// `Settings` scene. `SettingsLink` / `openSettings()` / `showSettingsWindow:`
/// have nothing to open once that scene is gone.
@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()

    enum Pane: String, Equatable {
        case general
        case webhook
        case about
        case extensions
        #if DEBUG
        case development
        #endif
    }

    /// Consumed by `SettingsView` when the window appears or this value changes.
    private(set) var pendingPane: Pane?

    /// Consumed by `WebhookSettingsPane` so a deep link pops Receive Logs.
    private(set) var pendingRevealWebhookRoot = false

    /// Consumed by `ExtensionSettingsPage` to open one plugin.
    private(set) var pendingExtensionID: String?

    /// Sidebar pane to restore when Settings is opened without a deep link.
    /// The view tree itself is released on close.
    private(set) var rememberedPaneID: String?

    /// Webhook root (tunnel / webhook menu & warning). Pops Receive Logs if open.
    func prepareRemoteWebhook() {
        pendingPane = .webhook
        pendingRevealWebhookRoot = true
        SettingsWindowController.shared.show()
    }

    /// Plugin page inside Extensions.
    func openExtension(id: String) {
        pendingPane = .extensions
        pendingRevealWebhookRoot = false
        pendingExtensionID = id
        SettingsWindowController.shared.show()
    }

    /// Plain Settings… / ⌘,. Drops a leftover deep link so the window does not
    /// jump to Webhook.
    func showSettings() {
        clearPendingDeepLink()
        SettingsWindowController.shared.show()
    }

    func rememberPane(id: String?) {
        rememberedPaneID = id
    }

    /// Drop a stale deep link (e.g. plain Settings… after a failed hop).
    func clearPendingDeepLink() {
        pendingPane = nil
        pendingRevealWebhookRoot = false
        pendingExtensionID = nil
    }

    func consumePendingPane() -> Pane? {
        let pane = pendingPane
        pendingPane = nil
        return pane
    }

    func consumePendingExtensionID() -> String? {
        let id = pendingExtensionID
        pendingExtensionID = nil
        return id
    }

    func consumePendingRevealWebhookRoot() -> Bool {
        let value = pendingRevealWebhookRoot
        pendingRevealWebhookRoot = false
        return value
    }
}
