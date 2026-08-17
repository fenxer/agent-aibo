import AiboCore
import AiboIngest
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WebhookSettingsPane: View {
    @State private var showsReceiveLogs = false
    @Bindable private var navigator = SettingsNavigator.shared

    var body: some View {
        Group {
            if showsReceiveLogs {
                ReceiveLogsSettingsView {
                    showsReceiveLogs = false
                }
            } else {
                WebhookSettingsRootView {
                    showsReceiveLogs = true
                }
            }
        }
        .onAppear { applyPendingReveal() }
        .onChange(of: navigator.pendingRevealWebhookRoot) { _, isPending in
            guard isPending else { return }
            applyPendingReveal()
        }
    }

    private func applyPendingReveal() {
        guard navigator.consumePendingRevealWebhookRoot() else { return }
        showsReceiveLogs = false
    }
}

private struct WebhookSettingsRootView: View {
    var onShowReceiveLogs: () -> Void

    var body: some View {
        Form {
            WebhookHeaderSection()
            WebhookListenerSection()
            WebhookConnectionSection()
            WebhookDismissRow()

            Section {
                ReceiveLogsEntryRow(action: onShowReceiveLogs)
            } header: {
                Text(String(localized: "Logs"))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Webhook"))
    }
}

private struct WebhookHeaderSection: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                WebhookHeaderIcon()

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Webhook"))
                        .font(.body.weight(.semibold))
                    Text(String(localized: "Listen on localhost to receive incoming webhooks"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle(
                    String(localized: "Listen on localhost"),
                    isOn: $settings.webhookEnabled
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            WebhookSetupLinkRow()
        }
    }
}

private struct WebhookHeaderIcon: View {
    private let side: CGFloat = 28
    private let iconSize: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.blue)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: "globe")
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private struct WebhookSetupLinkRow: View {
    var body: some View {
        Button {} label: {
            HStack {
                Text(String(localized: "Setup Guide"))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WebhookListenerSection: View {
    @State private var runtime = AiboRuntime.shared
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section {
            LabeledContent(String(localized: "Status")) {
                Text(
                    runtime.webhookListening
                        ? String(localized: "Running")
                        : String(localized: "Stopped")
                )
                .foregroundStyle(.secondary)
            }

            LabeledContent(String(localized: "Port")) {
                TextField(
                    String(localized: "Port"),
                    value: $settings.webhookPort,
                    format: .number.grouping(.never)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }

            LabeledContent(String(localized: "Local URL")) {
                HStack(spacing: 8) {
                    Text(settings.webhookURLString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    WebhookCopyButton(value: settings.webhookURLString)
                }
            }

            LabeledContent(String(localized: "Secret")) {
                HStack(spacing: 8) {
                    Text(maskedSecret(settings.webhookSecret))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    WebhookIconButton(
                        systemImage: "arrow.clockwise",
                        help: String(localized: "Regenerate Secret")
                    ) {
                        settings.regenerateWebhookSecret()
                    }
                    WebhookCopyButton(value: settings.webhookSecret)
                }
            }
        } header: {
            Text(String(localized: "Listener"))
        }
    }
}

private struct WebhookConnectionSection: View {
    @State private var runtime = AiboRuntime.shared
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section {
            LabeledContent(String(localized: "Tunnel URL")) {
                TextField(
                    String(localized: "https://…/webhook"),
                    text: $settings.publicWebhookURLString
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
            }

            LabeledContent(String(localized: "Connectivity")) {
                HStack(spacing: 8) {
                    Image(systemName: runtime.tunnelHealthStatus.menuSystemImage)
                        .foregroundStyle(connectivityColor)
                    Text(runtime.tunnelHealthStatus.settingsLabel)
                    Button(String(localized: "Check")) {
                        TunnelHealthMonitor.shared.scheduleCheck(reason: .manual)
                    }
                    .disabled(
                        !settings.webhookEnabled
                            || settings.resolvedPublicWebhookURL == nil
                            || runtime.tunnelHealthStatus == .checking
                    )
                }
            }
        }
    }

    private var connectivityColor: Color {
        switch runtime.tunnelHealthStatus {
        case .ok: .green
        case .down, .listenerStopped: .red
        case .checking, .unknown, .skipped: .secondary
        }
    }
}

private struct WebhookDismissRow: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section {
            LabeledContent(String(localized: "Dismiss Bubble")) {
                Picker(String(localized: "Dismiss Bubble"), selection: $settings.webhookDismissMode) {
                    ForEach(WebhookDismissMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            if settings.webhookDismissMode == .afterSeconds {
                LabeledContent(String(localized: "Seconds")) {
                    TextField(
                        String(localized: "Seconds"),
                        value: $settings.webhookAutoDismissSeconds,
                        format: .number
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                }
            }
        }
    }
}

private struct ReceiveLogsEntryRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(String(localized: "Received Logs"))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReceiveLogsSettingsView: View {
    var onBack: () -> Void

    @State private var runtime = AiboRuntime.shared
    @State private var searchText = ""
    @State private var selectedSource = ""
    @State private var confirmClear = false
    @State private var exportError: String?

    var body: some View {
        Group {
            if runtime.receiveLogEntries.isEmpty {
                ContentUnavailableView(
                    String(localized: "Received Logs"),
                    systemImage: "tray",
                    description: Text(
                        String(
                            localized: "Webhook deliveries show up here with timestamp and sender. The list shows the newest \(ReceiveLogStore.uiDisplayLimit); export includes everything on disk."
                        )
                    )
                )
            } else if displayedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ReceiveLogsFilterBar(
                        selectedSource: $selectedSource,
                        sources: uniqueSources
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    if let exportError {
                        ReceiveLogsExportError(message: exportError)
                    }
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Form {
                    if let exportError {
                        Section {
                            ReceiveLogsExportError(message: exportError)
                        }
                    }

                    Section {
                        ForEach(displayedEntries) { entry in
                            ReceiveLogsRow(entry: entry)
                        }
                    } header: {
                        ReceiveLogsFilterBar(
                            selectedSource: $selectedSource,
                            sources: uniqueSources
                        )
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(
            title: String(localized: "Received Logs"),
            canGoBack: true,
            onBack: onBack
        ) {
            ToolbarItem {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    TextField(String(localized: "Search"), text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 8)
                .frame(width: 180, height: ReceiveLogsToolbarMetrics.controlHeight)
                .background {
                    Color.clear
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Menu {
                    Button(String(localized: "Export")) {
                        exportLog()
                    }
                    .disabled(runtime.receiveLogEntries.isEmpty)

                    Button(String(localized: "Clear"), role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(runtime.receiveLogEntries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(
                            width: ReceiveLogsToolbarMetrics.controlHeight,
                            height: ReceiveLogsToolbarMetrics.controlHeight
                        )
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel(String(localized: "More"))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onChange(of: uniqueSources) { _, sources in
            if !selectedSource.isEmpty, !sources.contains(selectedSource) {
                selectedSource = ""
            }
        }
        .confirmationDialog(
            String(localized: "Clear all received logs?"),
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear"), role: .destructive) {
                runtime.clearReceiveLog()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    private var uniqueSources: [String] {
        Array(Set(runtime.receiveLogEntries.map(\.source))).sorted()
    }

    private var displayedEntries: [ReceiveLogEntry] {
        var entries = runtime.receiveLogEntries
        if !selectedSource.isEmpty {
            entries = entries.filter { $0.source == selectedSource }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.source.localizedCaseInsensitiveContains(query)
                || entry.message.localizedCaseInsensitiveContains(query)
        }
    }

    private func exportLog() {
        exportError = nil
        guard let data = runtime.exportReceiveLog() else {
            exportError = String(localized: "Failed to export received log")
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

private enum ReceiveLogsToolbarMetrics {
    static let controlHeight: CGFloat = 32
}

private struct ReceiveLogsFilterBar: View {
    @Binding var selectedSource: String
    var sources: [String]

    var body: some View {
        HStack {
            Text(String(localized: "Showing up to \(ReceiveLogStore.uiDisplayLimit) items"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            ReceiveLogsSourceMenu(selectedSource: $selectedSource, sources: sources)
        }
        .textCase(nil)
    }
}

private struct ReceiveLogsSourceMenu: View {
    @Binding var selectedSource: String
    var sources: [String]

    var body: some View {
        Menu {
            Button(String(localized: "All Sources")) {
                selectedSource = ""
            }
            ForEach(sources, id: \.self) { source in
                Button(source) {
                    selectedSource = source
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selectedSource.isEmpty ? String(localized: "All Sources") : selectedSource)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .foregroundStyle(selectedSource.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
        .textCase(nil)
    }
}

private struct ReceiveLogsExportError: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }
}

private struct ReceiveLogsRow: View {
    var entry: ReceiveLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    entry.receivedAt,
                    format: .relative(presentation: .numeric, unitsStyle: .abbreviated)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(entry.message)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

private struct WebhookIconButton: View {
    var systemImage: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct WebhookCopyButton: View {
    var value: String
    var help: String = String(localized: "Copy")

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            guard copyToPasteboard(value) else { return }
            withAnimation {
                didCopy = true
            }
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation {
                    didCopy = false
                }
            }
        } label: {
            ZStack {
                Image(systemName: "square.on.square")
                    .hidden()
                Image(systemName: didCopy ? "checkmark" : "square.on.square")
                    .contentTransition(
                        .symbolEffect(
                            .replace.magic(fallback: .downUp.byLayer),
                            options: .nonRepeating.speed(2)
                        )
                    )
            }
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .onDisappear {
            resetTask?.cancel()
        }
    }
}

private func copyToPasteboard(_ string: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(string, forType: .string)
}

private func maskedSecret(_ secret: String) -> String {
    guard secret.count >= 8 else { return String(repeating: "*", count: max(secret.count, 4)) }
    return "\(secret.prefix(4))****\(secret.suffix(4))"
}
