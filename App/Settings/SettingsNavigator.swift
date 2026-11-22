import AiboCore
import Foundation

/// Deep-links into Settings (Webhook, an extension, …) and presents the window.
///
/// In the main process, every `show*` entry spawns or focuses the isolated
/// `--role=settings` process through `SettingsProcessHost`. Inside the settings
/// process itself, incoming show requests populate the pending deep-link state
/// and raise `SettingsWindowController`.
@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()

    enum Pane: String, Equatable {
        case general
        case backup
        case webhook
        case about
        case extensions
        case tools
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

    /// Consumed by `ToolsSettingsPane` to open Hook Cleanup.
    private(set) var pendingToolsHookCleanup = false

    /// Sidebar pane to restore when Settings is opened without a deep link.
    /// The view tree itself is released on close.
    private(set) var rememberedPaneID: String?

    /// Webhook root (tunnel / webhook menu & warning). Pops Receive Logs if open.
    func prepareRemoteWebhook() {
        if AppProcessRole.isMain {
            SettingsProcessHost.shared.open(destination: .webhookRoot)
            return
        }
        pendingPane = .webhook
        pendingRevealWebhookRoot = true
        pendingToolsHookCleanup = false
        SettingsWindowController.shared.show()
    }

    /// Plugin page inside Extensions.
    func openExtension(id: String) {
        if AppProcessRole.isMain {
            SettingsProcessHost.shared.open(destination: .extensionDetail(id: id))
            return
        }
        pendingPane = .extensions
        pendingRevealWebhookRoot = false
        pendingExtensionID = id
        pendingToolsHookCleanup = false
        SettingsWindowController.shared.show()
    }

    /// Backup page, optionally starting an import preview for a Finder double-clicked archive.
    func showBackup(importArchiveURL: URL? = nil) {
        if AppProcessRole.isMain {
            SettingsProcessHost.shared.open(destination: .backup(importArchivePath: importArchiveURL?.path))
            return
        }
        pendingPane = .backup
        pendingRevealWebhookRoot = false
        pendingExtensionID = nil
        pendingToolsHookCleanup = false
        SettingsWindowController.shared.show()
        if let importArchiveURL {
            BackupSettingsModel.shared.importArchiveFromOutside(importArchiveURL)
        }
    }

    /// Tools → Hook Cleanup.
    func showHookCleanup() {
        if AppProcessRole.isMain {
            SettingsProcessHost.shared.open(destination: .hookCleanup)
            return
        }
        pendingPane = .tools
        pendingRevealWebhookRoot = false
        pendingExtensionID = nil
        pendingToolsHookCleanup = true
        SettingsWindowController.shared.show()
    }

    /// Plain Settings… / ⌘,. Drops a leftover deep link so the window does not
    /// jump to Webhook.
    func showSettings() {
        if AppProcessRole.isMain {
            SettingsProcessHost.shared.open(destination: .plain)
            return
        }
        clearPendingDeepLink()
        SettingsWindowController.shared.show()
    }

    /// Applies an incoming show command inside the settings process.
    func applyRemoteShow(destination: SettingsShowDestination, rememberedPaneID: String?) {
        if let rememberedPaneID {
            self.rememberedPaneID = rememberedPaneID
        }
        switch destination {
        case .plain:
            clearPendingDeepLink()
        case .webhookRoot:
            pendingPane = .webhook
            pendingRevealWebhookRoot = true
            pendingExtensionID = nil
            pendingToolsHookCleanup = false
        case .extensionDetail(let id):
            pendingPane = .extensions
            pendingRevealWebhookRoot = false
            pendingExtensionID = id
            pendingToolsHookCleanup = false
        case .backup(let importArchivePath):
            pendingPane = .backup
            pendingRevealWebhookRoot = false
            pendingExtensionID = nil
            pendingToolsHookCleanup = false
            if let importArchivePath {
                BackupSettingsModel.shared.startImportFromRemotePath(importArchivePath)
            }
        case .hookCleanup:
            pendingPane = .tools
            pendingRevealWebhookRoot = false
            pendingExtensionID = nil
            pendingToolsHookCleanup = true
        }
    }

    func rememberPane(id: String?) {
        rememberedPaneID = id
        if AppProcessRole.isSettings {
            SettingsProcessClient.shared.sendRememberPane(id)
        }
    }

    /// Drop a stale deep link (e.g. plain Settings… after a failed hop).
    func clearPendingDeepLink() {
        pendingPane = nil
        pendingRevealWebhookRoot = false
        pendingExtensionID = nil
        pendingToolsHookCleanup = false
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

    func consumePendingToolsHookCleanup() -> Bool {
        let value = pendingToolsHookCleanup
        pendingToolsHookCleanup = false
        return value
    }

    func consumePendingRevealWebhookRoot() -> Bool {
        let value = pendingRevealWebhookRoot
        pendingRevealWebhookRoot = false
        return value
    }
}
