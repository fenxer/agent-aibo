import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable {
    case pet
    case agentHook
    case appearance
    case integrations
    case receiveLog
    case about
    #if DEBUG
    case development
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pet: String(localized: "Pet")
        case .agentHook: String(localized: "Agent Hook")
        case .appearance: String(localized: "Appearance")
        case .integrations: String(localized: "Integrations")
        case .receiveLog: String(localized: "Receive Log")
        case .about: String(localized: "About")
        #if DEBUG
        case .development: String(localized: "Development")
        #endif
        }
    }

    enum Icon {
        case asset(String)
        case system(String)
    }

    var icon: Icon {
        switch self {
        case .pet: .asset("HeartMenu")
        case .agentHook: .system("point.bottomleft.forward.to.point.topright.scurvepath")
        case .appearance: .system("paintbrush.fill")
        case .integrations: .system("link")
        case .receiveLog: .system("tray.full")
        case .about: .system("info.circle")
        #if DEBUG
        case .development: .system("hammer")
        #endif
        }
    }

    var iconColor: Color {
        switch self {
        case .pet: .red
        case .agentHook: .blue
        case .appearance: .purple
        case .integrations: .blue
        case .receiveLog: .indigo
        case .about: Color(nsColor: .systemGray)
        #if DEBUG
        case .development: .orange
        #endif
        }
    }

    init?(_ destination: SettingsNavigator.Pane) {
        switch destination {
        case .appearance: self = .appearance
        case .integrations: self = .integrations
        case .receiveLog: self = .receiveLog
        case .about: self = .about
        #if DEBUG
        case .development: self = .development
        #endif
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach([SettingsPane.pet, .agentHook, .appearance, .integrations]) { pane in
                    SettingsSidebarRow(pane: pane)
                }
            }
            Section {
                SettingsSidebarRow(pane: .receiveLog)
            }
            Section {
                SettingsSidebarRow(pane: .about)
            }
            #if DEBUG
            Section {
                SettingsSidebarRow(pane: .development)
            }
            #endif
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        .toolbar(removing: .sidebarToggle)
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            SettingsSidebarIcon(pane: pane)
        }
        .tag(pane)
    }
}

private struct SettingsSidebarIcon: View {
    let pane: SettingsPane

    private let side: CGFloat = 24
    private let iconSize: CGFloat = 15

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
            .fill(pane.iconColor)
            .frame(width: side, height: side)
            .overlay {
                switch pane.icon {
                case .asset(let name):
                    Image(name)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                case .system(let name):
                    Image(systemName: name)
                        .font(.system(size: iconSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                }
            }
            .foregroundStyle(.white)
    }
}

struct SettingsView: View {
    @State private var selection: SettingsPane? = .pet
    @Bindable private var navigator = SettingsNavigator.shared

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
        } detail: {
            // Detail panes own in-column sub-navigation and apply
            // `settingsDetailChrome` for the System Settings–style toolbar.
            detailRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Fixed width; unbounded max height so `.windowResizability(.contentMinSize)`
        // reports "no maximum" and the window stays user-resizable in height.
        .frame(width: AppSettings.settingsWindowWidth)
        .frame(minHeight: AppSettings.settingsWindowMinHeight, maxHeight: .infinity)
        .background { SettingsWindowConfigurator() }
        .onAppear { applyPendingPane() }
        .onChange(of: navigator.pendingPane) { _, newValue in
            guard newValue != nil else { return }
            applyPendingPane()
        }
    }

    private func applyPendingPane() {
        guard let pending = navigator.consumePendingPane(),
              let pane = SettingsPane(pending)
        else { return }
        selection = pane
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection ?? .pet {
        case .pet:
            PetSettingsPane()
        case .agentHook:
            AgentHookSettingsPane()
        case .appearance:
            AppearanceSettingsPane()
        case .integrations:
            IntegrationsSettingsPane()
        case .receiveLog:
            ReceiveLogSettingsPane()
        case .about:
            AboutSettingsPane()
        #if DEBUG
        case .development:
            DevelopmentSettingsPane()
                .settingsDetailChrome(title: SettingsPane.development.title)
        #endif
        }
    }
}

private struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Theme"), selection: $settings.themeMode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(String(localized: "Theme"))
            }

            Section {
                Toggle(
                    String(localized: "Hide When Fullscreen"),
                    isOn: $settings.hideWhenFullscreen
                )

                Text(String(localized: "Temporarily hide the pet in native fullscreen (green-button Space) or when the system reports fullscreen presentation. Maximized windows stay visible. Does not change the Hide Pet menu state."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Pet"))
            }

            Section {
                Toggle(
                    String(localized: "Music Notes"),
                    isOn: $settings.musicNotesEnabled
                )

                Text(String(localized: "When any app reports Now Playing (Apple Music, Spotify, NetEase, …), notes float up from the pet. Uses MediaRemoteAdapter plus Music/Spotify distributed notifications as fallback."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup(String(localized: "Advanced")) {
                    TextField(
                        String(localized: "Custom notification names"),
                        text: $settings.customMusicNotificationNames,
                        prompt: Text("com.example.playerInfo"),
                        axis: .vertical
                    )
                    .lineLimit(3...6)

                    Text(String(localized: "Optional fallback: one distributed notification name per line. Payload should include Player State = Playing / Paused. Most Chinese clients do not post these — Now Playing covers them instead."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Music"))
            }

            Section {
                Picker(String(localized: "Bubble Position"), selection: $settings.bubblePlacement) {
                    ForEach(BubblePlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(String(localized: "Choose where the status popover appears relative to the pet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Status Bubble"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsDetailChrome(title: SettingsPane.appearance.title)
    }
}

private struct IntegrationsSettingsPane: View {
    @State private var runtime = PetRuntime.shared
    @Bindable private var settings = AppSettings.shared
    @Bindable private var navigator = SettingsNavigator.shared

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    Toggle(String(localized: "Listen on localhost"), isOn: $settings.webhookEnabled)

                    LabeledContent(String(localized: "Listener")) {
                        Text(
                            runtime.webhookListening
                                ? String(localized: "Running")
                                : String(localized: "Stopped")
                        )
                    }

                    LabeledContent(String(localized: "URL")) {
                        Text(settings.webhookURLString)
                            .textSelection(.enabled)
                    }

                    LabeledContent(String(localized: "Public URL")) {
                        TextField(
                            String(localized: "https://…/webhook"),
                            text: $settings.publicWebhookURLString
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent(String(localized: "Tunnel")) {
                        Text(runtime.tunnelHealthStatus.settingsLabel)
                    }

                    LabeledContent(String(localized: "Port")) {
                        TextField(
                            String(localized: "Port"),
                            value: $settings.webhookPort,
                            format: .number
                        )
                        .labelsHidden()
                        .frame(width: 80)
                    }

                    LabeledContent(String(localized: "Shared Secret")) {
                        Text(settings.webhookSecret)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    HStack {
                        Button(String(localized: "Copy URL")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.webhookURLString, forType: .string)
                        }
                        Button(String(localized: "Copy Secret")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.webhookSecret, forType: .string)
                        }
                        Button(String(localized: "Regenerate Secret")) {
                            settings.regenerateWebhookSecret()
                        }
                        Button(String(localized: "Check Tunnel")) {
                            TunnelHealthMonitor.shared.scheduleCheck(reason: .manual)
                        }
                        .disabled(
                            !settings.webhookEnabled
                                || settings.resolvedPublicWebhookURL == nil
                                || runtime.tunnelHealthStatus == .checking
                        )
                    }

                    Picker(String(localized: "Dismiss Bubble"), selection: $settings.webhookDismissMode) {
                        ForEach(WebhookDismissMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if settings.webhookDismissMode == .afterSeconds {
                        LabeledContent(String(localized: "Seconds")) {
                            TextField(
                                String(localized: "Seconds"),
                                value: $settings.webhookAutoDismissSeconds,
                                format: .number
                            )
                            .labelsHidden()
                            .frame(width: 64)
                        }
                    }

                    Text(String(localized: "Bound to 127.0.0.1 only. Set Public URL to your tunnel HTTPS endpoint (Cloudflare Tunnel, Tailscale Funnel, etc.) so aibo can warn after sleep if the tunnel is down. Requests are shown as raw bubble text for now — no LLM rewrite yet. Default dismiss is click; optional auto-dismiss uses the seconds above."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Remote Webhook"))
                }
                .id(SettingsNavigator.IntegrationsAnchor.remoteWebhook)
            }
            .formStyle(.grouped)
            .padding()
            .settingsDetailChrome(title: SettingsPane.integrations.title)
            .onAppear {
                scrollToPendingAnchor(using: proxy)
            }
            .onChange(of: navigator.pendingIntegrationsAnchor) { _, _ in
                scrollToPendingAnchor(using: proxy)
            }
        }
    }

    private func scrollToPendingAnchor(using proxy: ScrollViewProxy) {
        guard let anchor = navigator.consumePendingIntegrationsAnchor() else { return }
        Task { @MainActor in
            for delay in [Duration.milliseconds(16), .milliseconds(120)] {
                try? await Task.sleep(for: delay)
                withAnimation {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
    }
}

private struct ReceiveLogSettingsPane: View {
    @State private var runtime = PetRuntime.shared
    @State private var confirmClear = false
    @State private var exportError: String?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(receiveLogStatusText)
                .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "Export…")) {
                    exportLog()
                }
                .disabled(runtime.receiveLogEntries.isEmpty)

                Button(String(localized: "Clear"), role: .destructive) {
                    confirmClear = true
                }
                .disabled(runtime.receiveLogEntries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top)

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if runtime.receiveLogEntries.isEmpty {
                ContentUnavailableView(
                    String(localized: "Receive Log"),
                    systemImage: "tray",
                    description: Text(String(localized: "Webhook deliveries show up here with timestamp and sender. The list shows the newest 100; export includes everything on disk."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(runtime.receiveLogEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.source)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Spacer()
                            Text(Self.timestampFormatter.string(from: entry.receivedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .settingsDetailChrome(title: SettingsPane.receiveLog.title)
        .confirmationDialog(
            String(localized: "Clear all receive records?"),
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear"), role: .destructive) {
                runtime.clearReceiveLog()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    private var receiveLogStatusText: String {
        if runtime.receiveLogTotalCount == 0 {
            return String(localized: "No receive records yet.")
        }
        if runtime.receiveLogTotalCount > runtime.receiveLogEntries.count {
            return String(
                localized: "Showing \(runtime.receiveLogEntries.count) of \(runtime.receiveLogTotalCount)"
            )
        }
        return String(localized: "\(runtime.receiveLogTotalCount) records")
    }

    private func exportLog() {
        exportError = nil
        guard let data = runtime.exportReceiveLog() else {
            exportError = String(localized: "Failed to export receive log")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "aibo-receive-log.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = String(localized: "Failed to write export file")
        }
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Version")) {
                    Text(
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? "—"
                    )
                }
            } header: {
                Text(String(localized: "aibo"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsDetailChrome(title: SettingsPane.about.title)
    }
}

#Preview {
    SettingsView()
}
