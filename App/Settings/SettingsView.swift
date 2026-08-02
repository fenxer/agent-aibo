import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable {
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
        case .appearance: String(localized: "Appearance")
        case .integrations: String(localized: "Integrations")
        case .receiveLog: String(localized: "Receive Log")
        case .about: String(localized: "About")
        #if DEBUG
        case .development: String(localized: "Development")
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintbrush"
        case .integrations: "link"
        case .receiveLog: "tray.full"
        case .about: "info.circle"
        #if DEBUG
        case .development: "hammer"
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

struct SettingsView: View {
    @State private var selection: SettingsPane? = .appearance
    @Bindable private var navigator = SettingsNavigator.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // Avoid nesting NavigationStack inside the Settings scene — on recent
            // macOS the pushed back control lands under the title instead of the
            // window toolbar. Detail panes own any in-column sub-navigation.
            detailRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Fixed width; min height only so the window can grow (contentMinSize).
        .frame(width: AppSettings.settingsWindowWidth)
        .frame(minHeight: AppSettings.settingsWindowMinHeight)
        .background { SettingsWindowConfigurator() }
        .onAppear { applyPendingPane() }
        .onChange(of: navigator.pendingPane) { _, _ in
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
        switch selection ?? .appearance {
        case .appearance:
            AppearanceSettingsPane()
                .navigationTitle(SettingsPane.appearance.title)
        case .integrations:
            IntegrationsSettingsPane()
        case .receiveLog:
            ReceiveLogSettingsPane()
                .navigationTitle(SettingsPane.receiveLog.title)
        case .about:
            AboutSettingsPane()
                .navigationTitle(SettingsPane.about.title)
        #if DEBUG
        case .development:
            DevelopmentSettingsPane()
                .navigationTitle(SettingsPane.development.title)
        #endif
        }
    }
}

private struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    @Bindable private var library = PetLibraryStore.shared
    @State private var petdexInput = ""
    @State private var isImportingImage = false

    /// Labeled scale only — avoid `step:` which paints a tick at every increment.
    private static let petScaleTickPercents: [Double] = [0, 50, 100, 150, 200]

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
                Picker(String(localized: "Active Pet"), selection: selectedPetBinding) {
                    ForEach(library.records) { record in
                        Text(record.displayName).tag(record.id)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(
                        String(localized: "Petdex slug or URL"),
                        text: $petdexInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(library.isInstalling)

                    Button(String(localized: "Install")) {
                        let input = petdexInput
                        Task {
                            await library.installPetdex(from: input)
                            if library.lastErrorMessage == nil {
                                petdexInput = ""
                            }
                        }
                    }
                    .disabled(library.isInstalling || petdexInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Button(String(localized: "Add Image…")) {
                        isImportingImage = true
                    }
                    .disabled(library.isInstalling)

                    if library.selectedRecord.isRemovable {
                        Button(String(localized: "Remove Selected"), role: .destructive) {
                            library.remove(id: library.selectedID)
                        }
                    }
                }

                if library.isInstalling {
                    ProgressView(String(localized: "Installing…"))
                        .controlSize(.small)
                }

                if let error = library.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(String(localized: "Install a Petdex pet by slug (e.g. boba) or page URL. Or add a local square image. Default stays available."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Pet Library"))
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Slider(
                            value: petScalePercentBinding,
                            in: AppSettings.petScalePercentRange
                        ) {
                            EmptyView()
                        } ticks: {
                            SliderTickContentForEach(Self.petScaleTickPercents, id: \.self) { value in
                                SliderTick(value) {
                                    Text("\(Int(value))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        TextField(
                            String(localized: "Pet Size"),
                            value: petScalePercentIntBinding,
                            format: .number
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                        .monospacedDigit()

                        Text("%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } label: {
                    Text(String(localized: "Pet Size"))
                }

                if Int(settings.petScalePercent.rounded()) != Int(AppSettings.defaultPetScalePercent) {
                    Button(String(localized: "Reset Size")) {
                        settings.resetPetScalePercent()
                    }
                }

                Text(String(localized: "Scale the desktop pet image. 100% is the default size."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    String(localized: "Restore Last Position"),
                    isOn: $settings.restoreLastPetPosition
                )

                Text(String(localized: "Open the pet where you left it, using a screen-relative position so it adapts to different resolutions. Off always uses the bottom-right corner."))
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

            Section {
                Picker(String(localized: "Glass Style"), selection: $settings.bubbleGlassStyle) {
                    ForEach(BubbleGlassStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(String(localized: "Clear is see-through glass; Regular is the system glass; Translucent skips Liquid Glass and uses a soft fill."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ColorPicker(
                    String(localized: "Glass Tint"),
                    selection: glassTintBinding,
                    supportsOpacity: true
                )

                if settings.bubbleGlassTint != nil {
                    Button(String(localized: "Reset Tint")) {
                        settings.bubbleGlassTint = nil
                    }
                }

                Text(String(localized: "Optional color wash on the glass. Reset removes the tint."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Bubble Glass"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.png, .jpeg, .webP, .heic, .tiff, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImageImport(result)
        }
    }

    private var selectedPetBinding: Binding<String> {
        Binding(
            get: { library.selectedID },
            set: { library.select(id: $0) }
        )
    }

    private var petScalePercentBinding: Binding<Double> {
        Binding(
            get: { settings.petScalePercent },
            set: { settings.petScalePercent = $0.rounded() }
        )
    }

    private var petScalePercentIntBinding: Binding<Int> {
        Binding(
            get: { Int(settings.petScalePercent.rounded()) },
            set: { settings.petScalePercent = Double($0) }
        )
    }

    /// ColorPicker needs a non-optional `Color`; writing always enables a custom tint.
    private var glassTintBinding: Binding<Color> {
        Binding(
            get: { settings.bubbleGlassTint ?? .accentColor },
            set: { settings.bubbleGlassTint = $0 }
        )
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            library.importStaticImage(from: url)
        case .failure:
            break
        }
    }
}

private struct IntegrationsSettingsPane: View {
    @State private var runtime = PetRuntime.shared
    @Bindable private var settings = AppSettings.shared
    @State private var advancedAgent: AgentKind?

    var body: some View {
        Group {
            if let advancedAgent {
                AgentHookSpriteSettingsView(agent: advancedAgent) {
                    self.advancedAgent = nil
                }
                .navigationTitle("")
            } else {
                integrationsForm
                    .navigationTitle(SettingsPane.integrations.title)
            }
        }
    }

    private var integrationsForm: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Status")) {
                    Text(
                        runtime.cursorHooksInstalled
                            ? String(localized: "Installed")
                            : String(localized: "Not installed")
                    )
                }

                if runtime.cursorHooksInstalled {
                    Button(String(localized: "Uninstall Cursor Hooks")) {
                        runtime.uninstallCursorHooks()
                    }
                } else {
                    Button(String(localized: "Install Cursor Hooks")) {
                        runtime.installCursorHooks()
                    }
                }

                Text(String(localized: "Cursor has no approval / waiting-for-you hook event yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(String(localized: "Advanced Settings")) {
                    advancedAgent = .cursor
                }
            } header: {
                Text(String(localized: "Cursor"))
            }

            Section {
                LabeledContent(String(localized: "Status")) {
                    Text(
                        runtime.codexHooksInstalled
                            ? String(localized: "Installed")
                            : String(localized: "Not installed")
                    )
                }

                if runtime.codexHooksInstalled {
                    Button(String(localized: "Uninstall Codex Hooks")) {
                        runtime.uninstallCodexHooks()
                    }
                } else {
                    Button(String(localized: "Install Codex Hooks")) {
                        runtime.installCodexHooks()
                    }
                }

                Text(String(localized: "Codex shows an approval bubble via PermissionRequest."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(String(localized: "Advanced Settings")) {
                    advancedAgent = .codex
                }
            } header: {
                Text(String(localized: "Codex"))
            }

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
        }
        .formStyle(.grouped)
        .padding()
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
    }
}

#Preview {
    SettingsView()
}
