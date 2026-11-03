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

    @State private var webhookTemplate = WebhookTemplatePreview.defaultJSON
    @State private var webhookPreview = WebhookTemplatePreview.Content.placeholder
    @State private var webhookTemplateError: String?

    var body: some View {
        Form {
            WebhookHeaderSection()
            WebhookConnectionSection()
            WebhookListenerSection()
            WebhookPreviewBand(content: webhookPreview)
            WebhookTemplateEditor(
                template: $webhookTemplate,
                error: webhookTemplateError,
                onReset: resetWebhookTemplate,
                onPreview: previewWebhookTemplate
            )
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
        .onChange(of: webhookTemplate) { _, _ in
            webhookTemplateError = nil
        }
    }

    private func resetWebhookTemplate() {
        webhookTemplate = WebhookTemplatePreview.defaultJSON
        webhookTemplateError = nil
    }

    private func previewWebhookTemplate() {
        guard let content = WebhookTemplatePreview.content(for: webhookTemplate) else {
            webhookTemplateError = String(localized: "Couldn't read this JSON.")
            return
        }
        webhookTemplateError = nil
        webhookPreview = content
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

    var body: some View {
        Image("WebhookIcon")
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

private struct WebhookSetupLinkRow: View {
    private static let guideURL = URL(
        string: "https://github.com/fenxer/agent-aibo/tree/main/Skills/aibo-webhook"
    )

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = Self.guideURL {
                openURL(url)
            }
        } label: {
            HStack {
                Text(String(localized: "Setup Guide"))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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
        } header: {
            Text(String(localized: "Listener"))
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

/// Sample bubble plus the JSON the user can edit and apply with Preview.
private enum WebhookTemplatePreview {
    /// Token in the default template. The bubble shows field names instead of this.
    static let placeholderToken = "..."

    static let defaultJSON = """
    {
      "source": "...",
      "status": "...",
      "summary": "..."
    }
    """

    struct Content: Equatable {
        var source: String
        var status: String?
        var summary: String

        static let placeholder = Content(
            source: "source",
            status: "status",
            summary: "summary..."
        )
    }

    /// `nil` when `template` is not JSON. The untouched default template maps to
    /// `Content.placeholder` so the sample bubble does not render three dots.
    static func content(for template: String) -> Content? {
        let body = Data(template.utf8)
        guard (try? JSONSerialization.jsonObject(with: body)) != nil else { return nil }
        if isPlaceholder(body) { return .placeholder }
        let parsed = WebhookMessageFormatter.parse(from: body)
        let summary = parsed.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = summary.isEmpty ? parsed.displayText : summary
        return Content(source: parsed.source, status: parsed.status, summary: line)
    }

    private static func isPlaceholder(_ body: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            Set(object.keys) == ["source", "status", "summary"]
        else { return false }
        return (object["source"] as? String) == placeholderToken
            && (object["status"] as? String) == placeholderToken
            && (object["summary"] as? String) == placeholderToken
    }
}

private struct WebhookPreviewBand: View {
    var content: WebhookTemplatePreview.Content

    @Bindable private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private var colorScheme: ColorScheme {
        settings.themeMode.resolvedColorScheme(system: systemColorScheme)
    }

    var body: some View {
        Section {
            ZStack {
                GeometryReader { geo in
                    Image("WallpaperBg")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width + 20, height: geo.size.height + 20)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .accessibilityHidden(true)
                }

                WebhookPreviewBubble(content: content, colorScheme: colorScheme)
                    .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Preview"))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text(String(localized: "Preview"))
        }
    }
}

private struct WebhookPreviewBubble: View {
    var content: WebhookTemplatePreview.Content
    var colorScheme: ColorScheme

    var body: some View {
        // Same untinted webhook capsule as the desktop bubble: black pill, white label.
        let prefersLightLabel = StatusBubble.prefersLightLabel(
            tint: nil,
            style: .regular,
            colorScheme: colorScheme
        )
        let ink = prefersLightLabel ? Color.white : Color.black
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            Text(content.source)
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: textWidth(content.source, pointSize: 12, limit: 240), alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let status = content.status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background(Capsule().fill(Color.black))
                }

                Text(content.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(
                        width: textWidth(content.summary, pointSize: 14, limit: 200),
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background {
            StatusBubble.chromeMaterial(
                shape,
                style: .regular,
                tint: nil,
                suppressGlass: false
            )
        }
        .environment(\.colorScheme, colorScheme)
        .environment(
            \.backgroundProminence,
            prefersLightLabel ? .increased : .standard
        )
        .accessibilityHidden(true)
    }

    /// Single-line width, capped so a long summary wraps inside the preview.
    private func textWidth(_ text: String, pointSize: CGFloat, limit: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: pointSize)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return min(limit, max(ceil(width), 1))
    }
}

private struct WebhookTemplateEditor: View {
    @Binding var template: String
    var error: String?
    var onReset: () -> Void
    var onPreview: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(String(localized: "JSON"))
                    Spacer(minLength: 8)
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(template == WebhookTemplatePreview.defaultJSON)
                    .help(String(localized: "Reset"))
                    .accessibilityLabel(String(localized: "Reset"))

                    Button(action: onPreview) {
                        Text(String(localized: "Preview"))
                    }
                    .fixedSize()
                }

                TextEditor(text: $template)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 120)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
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
