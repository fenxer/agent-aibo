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
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection ?? .appearance {
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
                #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(selection?.title ?? String(localized: "Settings"))
        .frame(minWidth: 680, minHeight: 420)
    }
}

private struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
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
    }
}

private struct IntegrationsSettingsPane: View {
    @State private var runtime = PetRuntime.shared
    @Bindable private var settings = AppSettings.shared

    var body: some View {
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

                Text(String(localized: "Bound to 127.0.0.1 only. Public senders need your own tunnel (Cloudflare Tunnel, Tailscale Funnel, etc.). Requests are shown as raw bubble text for now — no LLM rewrite yet."))
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
    @State private var message = ""
    @State private var webhookJSON = """
        {
          "event": "statusChange",
          "id": "bc_test",
          "status": "FINISHED",
          "summary": "Added README.md with installation instructions"
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
                TextField(String(localized: "Message"), text: $message, axis: .vertical)
                    .lineLimit(2...5)

                HStack {
                    Button(String(localized: "Show Bubble")) {
                        runtime.showDebugBubble(message)
                    }
                    .disabled(!canShow)

                    Button(String(localized: "Clear Bubble")) {
                        runtime.clearDebugBubble()
                    }
                }

                Text(String(localized: "Adds a bubble on top of the stack. Cleared or overwritten by the next real agent event."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Bubble Preview"))
            }

            Section {
                TextEditor(text: $webhookJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)

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
