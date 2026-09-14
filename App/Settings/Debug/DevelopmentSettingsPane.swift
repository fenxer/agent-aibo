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
    @State private var stackBubbles = false
    @State private var isAwaitingApproval = false
    @State private var showsPlanProgress = false
    @State private var planProgressIntervalSeconds = 5
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
    @State private var runtime = AiboRuntime.shared

    private var canShow: Bool {
        if isAwaitingApproval { return true }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendWebhook: Bool {
        !webhookJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            bubblePreviewSection
            PlaytimeDebugSection()
            MouseShakeDebugSection()
            onboardingSection
            launchEntranceSection
            SoftwareUpdateDebugSection()
            webhookPreviewSection
            hookIngestLogSection
            hitRegionDebugSection
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
            TextField(text: $projectName) {
                Text(verbatim: "Project Name")
            }
            TextField(text: $modelName) {
                Text(verbatim: "Model Name")
            }
            TextField(text: $agentName) {
                Text(verbatim: "Agent Name")
            }
            .disabled(isSubagent)
            Toggle(isOn: $showCursorIcon) {
                Text(verbatim: "Show Cursor Icon")
            }
            .disabled(isAwaitingApproval || showsPlanProgress)
            Toggle(isOn: $isSubagent) {
                Text(verbatim: "Subagent Capsule")
            }
            .disabled(isAwaitingApproval || showsPlanProgress)
            Toggle(isOn: $stackBubbles) {
                Text(verbatim: "Stack Bubbles")
            }
            Toggle(isOn: $isAwaitingApproval) {
                Text(verbatim: "Approval Bubble")
            }
            Toggle(isOn: $showsPlanProgress) {
                Text(verbatim: "TODO Progress")
            }
            .disabled(isSubagent)
            if showsPlanProgress {
                LabeledContent {
                    TextField(
                        value: $planProgressIntervalSeconds,
                        format: .number
                    ) {
                        Text(verbatim: "Seconds")
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                } label: {
                    Text(verbatim: "Step Interval")
                }
            }
            TextField(text: $message, axis: .vertical) {
                Text(verbatim: "Status Text")
            }
            .lineLimit(2...5)
            .disabled(isAwaitingApproval)

            HStack {
                Button {
                    runtime.showDebugBubble(
                        text: message,
                        agentName: agentName,
                        projectName: projectName,
                        modelName: modelName,
                        showCursorIcon: showCursorIcon,
                        isSubagent: isSubagent,
                        stack: stackBubbles,
                        isAwaitingApproval: isAwaitingApproval,
                        showsPlanProgress: showsPlanProgress,
                        planProgressIntervalSeconds: planProgressIntervalSeconds
                    )
                } label: {
                    Text(verbatim: "Show Bubble")
                }
                .disabled(!canShow)

                Button {
                    runtime.showDebugTunnelWarningBubble()
                } label: {
                    Text(verbatim: "Show Warning Bubble")
                }

                Button {
                    runtime.clearDebugBubble()
                } label: {
                    Text(verbatim: "Clear Bubble")
                }
            }

            Text(verbatim: "Leave Project / Model empty to hide the header row. Cleared by the next real agent event.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Bubble Preview")
        }
    }

    private var onboardingSection: some View {
        Section {
            Button {
                runtime.clearDebugBubble()
                OnboardingController.shared.replay()
            } label: {
                Text(verbatim: "Replay Onboarding")
            }
            Text(verbatim: "Uses stock Poli (200%, -35 pt, right), moves slightly left and down from center, plays the portal jump, then starts the first-launch tour. Skip or finish restores the previous aibo, size, and position. Ordinary launches still skip the tour after the first time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Onboarding")
        }
    }

    private var launchEntranceSection: some View {
        Section {
            Button {
                AiboPanelController.shared.replayLaunchPortal()
            } label: {
                Text(verbatim: "Replay Launch Entrance")
            }
            Text(verbatim: "Plays the portal jump used when Aibo.app opens. Does not start onboarding.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Launch Entrance")
        }
    }

    private var webhookPreviewSection: some View {
        Section {
            TextEditor(text: $webhookJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 140)

            HStack {
                Button(action: injectWebhook) {
                    Text(verbatim: "Inject Webhook Bubble")
                }
                .disabled(!canSendWebhook)

                Button {
                    Task { await postWebhook() }
                } label: {
                    Text(verbatim: "POST to Local Listener")
                }
                .disabled(!canSendWebhook)
            }

            if let webhookStatus {
                Text(verbatim: webhookStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: "Inject skips HTTP and stacks a bubble from the payload text. POST signs the body and hits the localhost listener (enable it in Webhook settings first). Neither writes to Received Logs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Webhook Preview")
        }
    }

    private var hookIngestLogSection: some View {
        Section {
            Toggle(isOn: ingestLoggingBinding) {
                Text(verbatim: "Record Hook Ingest")
            }

            Text(verbatim: ingestLogStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button(action: copyIngestLog) {
                    Text(verbatim: "Copy Log")
                }
                .disabled(runtime.ingestLogEntryCount == 0)

                Button(role: .destructive) {
                    confirmClearIngest = true
                } label: {
                    Text(verbatim: "Clear")
                }
                .disabled(runtime.ingestLogEntryCount == 0)
            }

            if let ingestStatus {
                Text(verbatim: ingestStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: "Writes ~/Library/Application Support/aibo/ingest-log.jsonl. Each line has source (queue/socket), queuedAt, event, conversation, project, activity; Codex update_plan also fills detail with plan steps. Default on in DEBUG — turn off if noisy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Hook Ingest Log")
        }
        .confirmationDialog(
            "Clear hook ingest log?" as String,
            isPresented: $confirmClearIngest,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                runtime.clearIngestLog()
                ingestStatus = "Cleared"
            } label: {
                Text(verbatim: "Clear")
            }
            Button(role: .cancel) {
            } label: {
                Text(verbatim: "Cancel")
            }
        }
    }

    private var musicNotesSection: some View {
        Section {
            Toggle(isOn: debugMusicPlayingBinding) {
                Text(verbatim: "Simulate Music Playing")
            }

            Text(verbatim: "Forces the music-note rise overlay without a real player. General → Music Notes must stay on (default).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Music Notes")
        }
    }

    private var hitRegionDebugSection: some View {
        Section {
            Toggle(isOn: hitRegionDebugBinding) {
                Text(verbatim: "Show Hit Regions")
            }
            Text(verbatim: "Purple = panel · Orange = base pad · Yellow = music overflow · Blue = aiboHitRect · Green = opaque drag · Cyan = bubble hit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Hit Testing")
        }
    }

    private var hitRegionDebugBinding: Binding<Bool> {
        Binding(
            get: { AiboPanelController.shared.showHitRegionDebug },
            set: { AiboPanelController.shared.showHitRegionDebug = $0 }
        )
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
            return "Empty — \(path)"
        }
        return "\(count) lines — \(path)"
    }

    private func injectWebhook() {
        guard let data = webhookJSON.data(using: .utf8) else { return }
        runtime.ingestWebhookBody(data)
        webhookStatus = "Injected into bubble stack"
    }

    private func postWebhook() async {
        guard let data = webhookJSON.data(using: .utf8) else { return }
        if let error = await runtime.postTestWebhook(body: data) {
            webhookStatus = error
        } else {
            webhookStatus = "POST succeeded"
        }
    }

    private func copyIngestLog() {
        guard let text = runtime.copyIngestLogJSONL() else {
            ingestStatus = "Copy failed"
            return
        }
        if text.isEmpty {
            ingestStatus = "Log is empty"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ingestStatus = "Copied \(runtime.ingestLogEntryCount) lines"
    }
}
#endif
