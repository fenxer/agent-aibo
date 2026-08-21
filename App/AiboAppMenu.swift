import AiboCore
import AppKit
import SwiftUI

/// Shared command list for the menu bar extra and the aibo context menu.
struct AiboAppMenu: View {
    /// Context menu omits this: a live health-status rebuild dismisses the
    /// Change Aibo submenu and forces the user to re-select.
    var includesWebhookConnectivity: Bool = true

    @State private var aiboPanelController = AiboPanelController.shared
    @State private var runtime = AiboRuntime.shared
    @State private var settings = AppSettings.shared
    @State private var library = AiboLibraryStore.shared

    private var showsWebhookConnectivity: Bool {
        includesWebhookConnectivity
            && settings.webhookEnabled
            && settings.resolvedPublicWebhookURL != nil
    }

    var body: some View {
        // One Picker → one submenu. Wrapping this in `Menu` nests a second,
        // unlabeled submenu (empty pill) before the aibo list.
        Picker(String(localized: "Change Aibo"), selection: selectedAiboBinding) {
            ForEach(library.records) { record in
                Text(record.displayName).tag(record.id)
            }
        }
        .pickerStyle(.menu)

        if let lastErrorMessage = runtime.lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
                .foregroundStyle(.secondary)
        }

        Divider()

        if showsWebhookConnectivity {
            webhookConnectivityItem
        }

        // Must be SettingsLink — `openSettings()` / `showSettingsWindow:` log
        // "Please use SettingsLink…" and often no-op on current SDKs.
        // Deep-link clear for this item is handled in `NSMenu.willSendActionNotification`.
        SettingsLink {
            Text(String(localized: "Settings…"))
        }

        Divider()

        Button {
            aiboPanelController.toggle()
        } label: {
            Text(
                aiboPanelController.isVisible
                    ? String(localized: "Hide Aibo")
                    : String(localized: "Show Aibo")
            )
        }

        Button(String(localized: "Quit Aibo")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var selectedAiboBinding: Binding<String> {
        Binding(
            get: { library.selectedID },
            set: { library.select(id: $0) }
        )
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
