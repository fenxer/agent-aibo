import AppKit
import SwiftUI

/// Shared command list for the menu bar extra and the aibo context menu.
struct AiboAppMenu: View {
    @State private var aiboPanelController = AiboPanelController.shared
    @State private var runtime = AiboRuntime.shared
    @State private var settings = AppSettings.shared

    private var showsWebhookConnectivity: Bool {
        settings.webhookEnabled && settings.resolvedPublicWebhookURL != nil
    }

    var body: some View {
        Button {
            aiboPanelController.toggle()
        } label: {
            Text(
                aiboPanelController.isVisible
                    ? String(localized: "Hide Aibo")
                    : String(localized: "Show Aibo")
            )
        }

        if let lastErrorMessage = runtime.lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
                .foregroundStyle(.secondary)
        }

        if showsWebhookConnectivity {
            Divider()
            webhookConnectivityItem
        }

        Divider()

        // Must be SettingsLink — `openSettings()` / `showSettingsWindow:` log
        // "Please use SettingsLink…" and often no-op on current SDKs.
        // Deep-link clear for this item is handled in `NSMenu.willSendActionNotification`.
        SettingsLink {
            Text(String(localized: "Settings…"))
        }

        Divider()

        Button(String(localized: "Quit aibo")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Opens Settings via `SettingsLink`. Deep link is armed in
    /// `NSMenu.willSendActionNotification` (menu gestures do not run).
    ///
    /// `Label` → AppKit menu image + title (SF Symbol survives). Custom `HStack`
    /// `Image` is often stripped from menu items.
    private var webhookConnectivityItem: some View {
        SettingsLink {
            Label(
                String(localized: "Webhook Connectivity"),
                systemImage: runtime.tunnelHealthStatus.menuSystemImage
            )
        }
        .help(runtime.tunnelHealthStatus.settingsLabel)
        .onAppear {
            TunnelHealthMonitor.shared.scheduleCheck(reason: .manual)
        }
    }
}
