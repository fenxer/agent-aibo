import AppKit
import Foundation

/// Deep-links into the Settings scene sidebar (Webhook, etc.).
///
/// Opening Settings must go through `SettingsLink` (calling `openSettings()` /
/// `showSettingsWindow:` warns and often no-ops on current SDKs).
///
/// Menu `TapGesture` / `simultaneousGesture` do **not** run on AppKit menu items.
/// Deep links from the webhook `SettingsLink` are armed in
/// `NSMenu.willSendActionNotification` before the link’s action opens Settings.
@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()

    enum Pane: String, Equatable {
        case appearance
        case webhook
        case about
        #if DEBUG
        case development
        #endif
    }

    /// Consumed by `SettingsView` when the window appears or this value changes.
    private(set) var pendingPane: Pane?

    /// Consumed by `WebhookSettingsPane` so a deep link pops Receive Logs.
    private(set) var pendingRevealWebhookRoot = false

    private var bringToFrontTask: Task<Void, Never>?
    private var menuWillSendActionObserver: NSObjectProtocol?

    /// Install once at launch — menu `SettingsLink` deep links rely on this.
    func start() {
        guard menuWillSendActionObserver == nil else { return }
        menuWillSendActionObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.willSendActionNotification,
            object: nil,
            queue: .main
        ) { note in
            MainActor.assumeIsolated {
                SettingsNavigator.shared.handleMenuWillSendAction(note)
            }
        }
    }

    /// Webhook root (tunnel / webhook menu & warning). Pops Receive Logs if open.
    func prepareRemoteWebhook() {
        pendingPane = .webhook
        pendingRevealWebhookRoot = true
        prepareForOpeningSettings()
    }

    /// Call alongside `SettingsLink` (warning bubble, etc.) so accessory apps can key.
    func prepareForOpeningSettings() {
        activateForSettings()
        scheduleBringSettingsWindowToFront()
    }

    /// Drop a stale deep link (e.g. plain Settings… after a failed hop).
    func clearPendingDeepLink() {
        pendingPane = nil
        pendingRevealWebhookRoot = false
    }

    func consumePendingPane() -> Pane? {
        let pane = pendingPane
        pendingPane = nil
        return pane
    }

    func consumePendingRevealWebhookRoot() -> Bool {
        let value = pendingRevealWebhookRoot
        pendingRevealWebhookRoot = false
        return value
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

    private func handleMenuWillSendAction(_ note: Notification) {
        guard let item = note.userInfo?["MenuItem"] as? NSMenuItem else { return }

        if menuItemMatchesWebhookConnectivity(item) {
            // Before SettingsLink opens Settings — pending is ready for onAppear/onChange.
            pendingPane = .webhook
            pendingRevealWebhookRoot = true
            prepareForOpeningSettings()
            return
        }

        if menuItemMatchesPlainSettings(item) {
            // Do not reuse a leftover webhook deep link from an earlier click.
            clearPendingDeepLink()
            prepareForOpeningSettings()
        }
    }

    private func menuItemMatchesWebhookConnectivity(_ item: NSMenuItem) -> Bool {
        let title = String(localized: "Webhook Connectivity")
        return menuItem(item, matchesTitle: title)
    }

    private func menuItemMatchesPlainSettings(_ item: NSMenuItem) -> Bool {
        let title = String(localized: "Settings…")
        return menuItem(item, matchesTitle: title)
    }

    private func menuItem(_ item: NSMenuItem, matchesTitle title: String) -> Bool {
        if item.title == title || item.title.hasPrefix(title) { return true }
        if let attributed = item.attributedTitle?.string,
           attributed == title || attributed.hasPrefix(title)
        {
            return true
        }
        if item.accessibilityLabel() == title { return true }
        return false
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
