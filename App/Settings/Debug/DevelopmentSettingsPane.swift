#if DEBUG
import AppKit
import AiboCore
import SwiftUI

/// Settings → Development. DEBUG-only local previews and probes.
struct DevelopmentSettingsPane: View {
    @State private var projectName = "design-fragments"
    @State private var modelName = "Grok 4.5 High Fast"
    @State private var agentName = "Cursor"
    @State private var showCursorIcon = true
    @State private var isSubagent = false
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
    @State private var ingestStatus: String?
    @State private var confirmClearIngest = false
    @State private var runtime = PetRuntime.shared

    private var canShow: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendWebhook: Bool {
        !webhookJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            bubblePreviewSection
            webhookPreviewSection
            hookIngestLogSection
            musicNotesSection
            MediaRemotePayloadDebugSection()
            DistributedNotificationSnifferSection()
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            runtime.refreshIngestLogCount()
        }
        .onDisappear {
            DistributedNotificationSniffer.shared.stop()
        }
    }

    private var bubblePreviewSection: some View {
        Section {
            TextField(String(localized: "Project Name"), text: $projectName)
            TextField(String(localized: "Model Name"), text: $modelName)
            TextField(String(localized: "Agent Name"), text: $agentName)
                .disabled(isSubagent)
            Toggle(String(localized: "Show Cursor Icon"), isOn: $showCursorIcon)
            Toggle(String(localized: "Subagent Capsule"), isOn: $isSubagent)
            TextField(String(localized: "Status Text"), text: $message, axis: .vertical)
                .lineLimit(2...5)

            HStack {
                Button(String(localized: "Show Bubble")) {
                    runtime.showDebugBubble(
                        text: message,
                        agentName: agentName,
                        projectName: projectName,
                        modelName: modelName,
                        showCursorIcon: showCursorIcon,
                        isSubagent: isSubagent
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
    }

    private var webhookPreviewSection: some View {
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

    private var hookIngestLogSection: some View {
        Section {
            Toggle(
                String(localized: "Record Hook Ingest"),
                isOn: ingestLoggingBinding
            )

            Text(ingestLogStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button(String(localized: "Copy Log")) {
                    copyIngestLog()
                }
                .disabled(runtime.ingestLogEntryCount == 0)

                Button(String(localized: "Clear"), role: .destructive) {
                    confirmClearIngest = true
                }
                .disabled(runtime.ingestLogEntryCount == 0)
            }

            if let ingestStatus {
                Text(ingestStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(String(localized: "Writes ~/Library/Application Support/aibo/ingest-log.jsonl. Each line has source (queue/socket), queuedAt, event, conversation, project, activity. Default on in DEBUG — turn off if noisy."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Hook Ingest Log"))
        }
        .confirmationDialog(
            String(localized: "Clear hook ingest log?"),
            isPresented: $confirmClearIngest,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear"), role: .destructive) {
                runtime.clearIngestLog()
                ingestStatus = String(localized: "Cleared")
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    private var musicNotesSection: some View {
        Section {
            Toggle(
                String(localized: "Simulate Music Playing"),
                isOn: debugMusicPlayingBinding
            )

            Text(String(localized: "Forces the music-note rise overlay without a real player. Appearance → Music Notes must stay on (default)."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Music Notes"))
        }
    }

    private var ingestLoggingBinding: Binding<Bool> {
        Binding(
            get: { runtime.ingestLoggingEnabled },
            set: { runtime.setIngestLoggingEnabled($0) }
        )
    }

    private var debugMusicPlayingBinding: Binding<Bool> {
        Binding(
            get: { MusicPlaybackMonitor.shared.debugForcePlaying },
            set: { MusicPlaybackMonitor.shared.debugForcePlaying = $0 }
        )
    }

    private var ingestLogStatusText: String {
        let count = runtime.ingestLogEntryCount
        let path = AiboPaths.ingestLogURL.path
        if count == 0 {
            return String(localized: "Empty — \(path)")
        }
        return String(localized: "\(count) lines — \(path)")
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

    private func copyIngestLog() {
        guard let text = runtime.copyIngestLogJSONL() else {
            ingestStatus = String(localized: "Copy failed")
            return
        }
        if text.isEmpty {
            ingestStatus = String(localized: "Log is empty")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ingestStatus = String(localized: "Copied \(runtime.ingestLogEntryCount) lines")
    }
}
#endif
