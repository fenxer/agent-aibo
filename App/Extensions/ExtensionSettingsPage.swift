import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExtensionSettingsPage: View {
    var onBack: () -> Void

    @State private var center = ExtensionCenter.shared
    @State private var detailID: String?
    @State private var pendingEnable: ExtensionRecord?
    @State private var installError: String?

    var body: some View {
        Group {
            if let detailID, let record = center.plugins.first(where: { $0.id == detailID }) {
                ExtensionDetailPage(record: record, center: center) {
                    self.detailID = nil
                }
            } else {
                list
            }
        }
        .onChange(of: center.plugins.map(\.id)) { _, ids in
            if let detailID, !ids.contains(detailID) {
                self.detailID = nil
            }
        }
    }

    private var list: some View {
        Group {
            if center.plugins.isEmpty {
                ContentUnavailableView {
                    Text(String(localized: "No plugins installed"))
                } description: {
                    Text(String(localized: "Install a plugin folder, or install the included prototypes. Plugins stay off until you turn one on."))
                }
            } else {
                Form {
                    Section {
                        ForEach(center.plugins) { record in
                            ExtensionListRow(record: record) {
                                detailID = record.id
                            } onToggle: { enabled in
                                if enabled {
                                    pendingEnable = record
                                } else {
                                    center.setEnabled(false, id: record.id)
                                }
                            }
                        }
                    } footer: {
                        Text(String(localized: "Plugins stay off until you turn one on."))
                            .font(.caption)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Plugins"), canGoBack: true, onBack: onBack) {
            ToolbarItem(placement: .automatic) {
                installButtons
            }
        }
        .alert(
            String(localized: "Turn On “\(pendingEnable?.copy.name ?? "")”?"),
            isPresented: Binding(
                get: { pendingEnable != nil },
                set: { if !$0 { pendingEnable = nil } }
            ),
            presenting: pendingEnable
        ) { record in
            Button(String(localized: "Turn On")) {
                center.setEnabled(true, id: record.id)
                pendingEnable = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingEnable = nil
            }
        } message: { record in
            Text(ExtensionPermissionText.summary(record.permissionFacts))
        }
        .alert(
            String(localized: "Couldn't install the plugin."),
            isPresented: Binding(
                get: { installError != nil },
                set: { if !$0 { installError = nil } }
            )
        ) {
            Button(String(localized: "Done")) { installError = nil }
        }
        .onChange(of: center.lastError) { _, newValue in
            installError = newValue
        }
    }

    private var installButtons: some View {
        HStack {
            Button(String(localized: "Install Included Prototypes")) {
                center.installIncludedPrototypes()
            }
            Button(String(localized: "Install from Folder…")) {
                installFromFolder()
            }
        }
    }

    private func installFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Install")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        center.install(from: url)
    }
}

private struct ExtensionListRow: View {
    var record: ExtensionRecord
    var onOpen: () -> Void
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.copy.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(record.copy.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !record.copy.inputs.isEmpty {
                        Text(String(localized: "Input: \(record.copy.inputs.joined(separator: ", "))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !record.copy.outputs.isEmpty {
                        Text(String(localized: "Output: \(record.copy.outputs.joined(separator: ", "))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !record.permissionFacts.isEmpty {
                        Text(String(localized: "Permissions: \(ExtensionPermissionText.inline(record.permissionFacts))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "Calls: \(record.invocations)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(isOn: Binding(get: { record.enabled }, set: onToggle)) {
                Text(record.copy.name)
            }
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct ExtensionDetailPage: View {
    var record: ExtensionRecord
    var center: ExtensionCenter
    var onBack: () -> Void

    @State private var drafts: [String: String] = [:]
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.copy.name)
                            .font(.body.weight(.semibold))
                        Text(record.copy.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(isOn: Binding(
                        get: { record.enabled },
                        set: { center.setEnabled($0, id: record.id) }
                    )) {
                        Text(record.copy.name)
                    }
                    .labelsHidden()
                }
                if !record.copy.inputs.isEmpty {
                    LabeledContent(String(localized: "Input")) {
                        Text(record.copy.inputs.joined(separator: ", "))
                    }
                }
                if !record.copy.outputs.isEmpty {
                    LabeledContent(String(localized: "Output")) {
                        Text(record.copy.outputs.joined(separator: ", "))
                    }
                }
                if !record.permissionFacts.isEmpty {
                    LabeledContent(String(localized: "Permissions")) {
                        Text(ExtensionPermissionText.inline(record.permissionFacts))
                    }
                }
                LabeledContent(String(localized: "Calls")) {
                    Text("\(record.invocations)")
                }
            }

            if let schema = record.manifest.settings, !schema.orderedKeys.isEmpty {
                Section {
                    ForEach(schema.orderedKeys, id: \.self) { key in
                        if let field = schema.properties[key] {
                            fieldControl(key: key, field: field)
                        }
                    }
                } header: {
                    Text(String(localized: "Plugin Settings"))
                }
            }

            Section {
                Button(String(localized: "Uninstall"), role: .destructive) {
                    confirmUninstall = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: record.copy.name, canGoBack: true, onBack: {
            center.saveSettings(id: record.id, drafts: drafts)
            onBack()
        })
        .onAppear {
            drafts = center.settingsValues(for: record.id)
        }
        .onDisappear {
            center.saveSettings(id: record.id, drafts: drafts)
        }
        .confirmationDialog(
            String(localized: "Uninstall “\(record.copy.name)”?"),
            isPresented: $confirmUninstall,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Uninstall"), role: .destructive) {
                center.uninstall(id: record.id)
                onBack()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This removes the plugin and its settings."))
        }
    }

    @ViewBuilder
    private func fieldControl(key: String, field: ExtensionFieldSchema) -> some View {
        let title = ExtensionCopyResolver.fieldTitle(
            group: "settings",
            key: key,
            field: field,
            strings: record.strings
        )
        let summary = ExtensionCopyResolver.fieldSummary(
            group: "settings",
            key: key,
            field: field,
            strings: record.strings
        )
        if !field.oneOf.isEmpty {
            Picker(title, selection: draftBinding(key)) {
                ForEach(field.oneOf, id: \.value) { choice in
                    Text(
                        ExtensionCopyResolver.choiceTitle(
                            group: "settings",
                            key: key,
                            choice: choice,
                            strings: record.strings
                        )
                    )
                    .tag(choice.value)
                }
            }
        } else if field.sensitive {
            SecureField(title, text: draftBinding(key))
            if center.hasSavedSecret(id: record.id, key: key) {
                Text(String(localized: "Leave blank to keep the saved key."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            TextField(title, text: draftBinding(key))
        }
        if let summary, !summary.isEmpty {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func draftBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { drafts[key] ?? "" },
            set: { drafts[key] = $0 }
        )
    }
}

enum ExtensionPermissionText {
    static func inline(_ facts: ExtensionPermissionFacts) -> String {
        parts(facts).joined(separator: ", ")
    }

    static func summary(_ facts: ExtensionPermissionFacts) -> String {
        let lines = parts(facts)
        if lines.isEmpty {
            return String(localized: "No extra permissions")
        }
        return lines.joined(separator: "\n")
    }

    private static func parts(_ facts: ExtensionPermissionFacts) -> [String] {
        var lines: [String] = []
        if facts.usesModel {
            lines.append(String(localized: "Model"))
        }
        if facts.providesModel {
            lines.append(String(localized: "Provides a model to other plugins"))
        }
        var hosts = facts.networkHosts
        if facts.allowsConfiguredEndpoint {
            hosts.append(String(localized: "Configured endpoint"))
        }
        if !hosts.isEmpty {
            lines.append(String(localized: "Network: \(hosts.joined(separator: ", "))"))
        }
        return lines
    }
}
