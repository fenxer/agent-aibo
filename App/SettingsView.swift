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
}

struct SettingsView: View {
    @State private var selection: SettingsPane? = .appearance

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
        .frame(minWidth: 680, minHeight: 420)
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

    private static let petScaleTickStep: Double = 50

    var body: some View {
        Form {
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
                Slider(
                    value: $settings.petScalePercent,
                    in: AppSettings.petScalePercentRange,
                    step: 1
                ) {
                    Text(String(localized: "Pet Size"))
                } currentValueLabel: {
                    Text(petScalePercentLabel)
                        .monospacedDigit()
                } minimumValueLabel: {
                    Text("0%")
                } maximumValueLabel: {
                    Text("200%")
                } tick: { value in
                    petScaleTick(for: value)
                }

                if Int(settings.petScalePercent.rounded()) != Int(AppSettings.defaultPetScalePercent) {
                    Button(String(localized: "Reset Size")) {
                        settings.resetPetScalePercent()
                    }
                }

                Text(String(localized: "Scale the desktop pet image. 100% is the default size."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Pet"))
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

    private var petScalePercentLabel: String {
        "\(Int(settings.petScalePercent.rounded()))%"
    }

    /// Marks every 50%; intermediate 1% steps stay unlabeled.
    private func petScaleTick(for value: Double) -> SliderTick<Double>? {
        let percent = Int(value.rounded())
        guard percent % Int(Self.petScaleTickStep) == 0 else { return nil }
        return SliderTick(Double(percent)) {
            Text("\(percent)%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

                Text(String(localized: "Cursor has no waiting-for-user hook event yet."))
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

                Text(String(localized: "Codex supports waiting-for-you via PermissionRequest."))
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

                Text(String(localized: "Bound to 127.0.0.1 only. Public senders need your own tunnel (Cloudflare Tunnel, Tailscale Funnel, etc.). Requests are shown as raw bubble text for now — no LLM rewrite yet. Default dismiss is click; optional auto-dismiss uses the seconds above."))
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

#if DEBUG
private struct DevelopmentSettingsPane: View {
    @State private var projectName = "design-fragments"
    @State private var modelName = "Grok 4.5 High Fast"
    @State private var agentName = "Cursor"
    @State private var showCursorIcon = true
    @State private var message = "is thinking"
    @State private var webhookJSON = """
        {
          "source": "Deploy Bot",
          "status": "FINISHED",
          "summary": "deployed main@abc1234",
          "event": "workers.deploy",
          "id": "build-test-1"
        }
        """
    @State private var webhookStatus: String?
    @State private var runtime = PetRuntime.shared

    private var canShow: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendWebhook: Bool {
        !webhookJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Project Name"), text: $projectName)
                TextField(String(localized: "Model Name"), text: $modelName)
                TextField(String(localized: "Agent Name"), text: $agentName)
                Toggle(String(localized: "Show Cursor Icon"), isOn: $showCursorIcon)
                TextField(String(localized: "Status Text"), text: $message, axis: .vertical)
                    .lineLimit(2...5)

                HStack {
                    Button(String(localized: "Show Bubble")) {
                        runtime.showDebugBubble(
                            text: message,
                            agentName: agentName,
                            projectName: projectName,
                            modelName: modelName,
                            showCursorIcon: showCursorIcon
                        )
                    }
                    .disabled(!canShow)

                    Button(String(localized: "Clear Bubble")) {
                        runtime.clearDebugBubble()
                    }
                }

                Text(String(localized: "Leave Project / Model empty to hide the header row. Cleared or overwritten by the next real agent event."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Bubble Preview"))
            }

            Section {
                TextEditor(text: $webhookJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 140)

                HStack {
                    Button(String(localized: "Inject Webhook Bubble")) {
                        injectWebhook()
                    }
                    .disabled(!canSendWebhook)

                    Button(String(localized: "POST to Local Listener")) {
                        Task { await postWebhook() }
                    }
                    .disabled(!canSendWebhook)
                }

                if let webhookStatus {
                    Text(webhookStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(String(localized: "Inject skips HTTP and stacks a bubble from the payload text. POST signs the body and hits the localhost listener (enable it in Integrations first)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Webhook Preview"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func injectWebhook() {
        guard let data = webhookJSON.data(using: .utf8) else { return }
        runtime.ingestWebhookBody(data)
        webhookStatus = String(localized: "Injected into bubble stack")
    }

    private func postWebhook() async {
        guard let data = webhookJSON.data(using: .utf8) else { return }
        if let error = await runtime.postTestWebhook(body: data) {
            webhookStatus = error
        } else {
            webhookStatus = String(localized: "POST succeeded")
        }
    }
}
#endif

#Preview {
    SettingsView()
}
