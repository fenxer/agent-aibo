import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An extension the app can offer before it is installed.
/// The list will come from outside the app bundle. No source is chosen yet.
private struct ExtensionOffer: Identifiable, Equatable {
    var id: String
    var name: String
    var summary: String

    static let placeholder: [ExtensionOffer] = []
}

struct ExtensionSettingsPage: View {
    @State private var center = ExtensionCenter.shared
    @State private var detailID: String?
    @State private var installError: String?

    var body: some View {
        Group {
            if let detailID, let record = center.plugins.first(where: { $0.id == detailID }) {
                ExtensionDetailPage(record: record, center: center, onOpenPlugin: { id in
                    self.detailID = id
                }) {
                    self.detailID = nil
                }
                .id(record.id)
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

    private var offers: [ExtensionOffer] {
        let installedIDs = Set(center.plugins.map(\.id))
        return ExtensionOffer.placeholder.filter { !installedIDs.contains($0.id) }
    }

    private var list: some View {
        Form {
            Section {
                ExtensionIntroRow()
            }

            if !center.plugins.isEmpty {
                Section {
                    ForEach(center.plugins) { record in
                        ExtensionInstalledRow(record: record) {
                            detailID = record.id
                        }
                    }
                } header: {
                    Text(String(localized: "Installed"))
                }
            }

            if !offers.isEmpty {
                Section {
                    ForEach(offers) { offer in
                        ExtensionOfferRow(offer: offer) {
                            installOffer(offer)
                        }
                    }
                } header: {
                    Text(String(localized: "Uninstalled"))
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Extensions")) {
            ToolbarItem(placement: .automatic) {
                installButtons
            }
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
        Button {
            installFromFolder()
        } label: {
            Text(String(localized: "Install from Folder…"))
                .padding(.horizontal, 4)
        }
    }

    private func installOffer(_ offer: ExtensionOffer) {
        // Nothing to fetch until an external list exists.
        _ = offer
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

private struct ExtensionIntroRow: View {
    private let side: CGFloat = 28
    private let iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.teal)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: iconSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Extensions"))
                    .font(.body.weight(.semibold))
                Text(String(localized: "Add extra capabilities for Aibo"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExtensionInstalledRow: View {
    var record: ExtensionRecord
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ExtensionRowIcon(icon: record.manifest.icon, directory: record.directory)
                ExtensionRowCopy(name: record.copy.name, summary: record.copy.summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(localized: "Installed"))
                    .foregroundStyle(.green)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ExtensionOfferRow: View {
    var offer: ExtensionOffer
    var onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ExtensionRowIcon(directory: nil)
            ExtensionRowCopy(name: offer.name, summary: offer.summary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Install"), action: onInstall)
        }
    }
}

private struct ExtensionRowCopy: View {
    var name: String
    var summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ExtensionRowIcon: View {
    var icon: ExtensionIcon = .fallback
    var directory: URL?

    var body: some View {
        ExtensionIconBadge(
            icon: icon,
            directory: directory,
            side: 28,
            cornerRadius: 6,
            symbolPointSize: 14
        )
    }
}

private enum ExtensionRelation {
    case dependsOn
    case usedBy

    var title: String {
        switch self {
        case .dependsOn: String(localized: "Depends On")
        case .usedBy: String(localized: "Used By")
        }
    }
}

private struct ProviderEditorToken: Identifiable {
    var id: String
    var isNew: Bool
    var displayName: String
    var values: [String: String]
}

struct ExtensionDetailPage: View {
    var record: ExtensionRecord
    var center: ExtensionCenter
    var onOpenPlugin: (String) -> Void
    var onBack: () -> Void

    @State private var drafts: [String: String] = [:]
    @State private var providers: [ExtensionProvider] = []
    @State private var relation: ExtensionRelation?
    @State private var editor: ProviderEditorToken?
    @State private var confirmEnable = false
    @State private var confirmUninstall = false

    var body: some View {
        Group {
            if let relation {
                relationList(relation)
            } else {
                detailForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: pageTitle, canGoBack: true, onBack: goBack)
        .onAppear(perform: load)
        .onDisappear {
            guard !record.manifest.providesModel else { return }
            center.saveSettings(id: record.id, drafts: drafts)
        }
        .sheet(item: $editor) { token in
            ProviderEditorSheet(
                record: record,
                token: token,
                hasSavedKey: center.providerHasSecret(pluginID: record.id, providerID: token.id),
                onSave: { provider, apiKey in
                    center.saveProvider(pluginID: record.id, provider: provider, apiKeyDraft: apiKey)
                    reloadProviders()
                    editor = nil
                },
                onDelete: {
                    center.deleteProvider(pluginID: record.id, providerID: token.id)
                    reloadProviders()
                    editor = nil
                },
                onCancel: { editor = nil }
            )
        }
        .alert(
            String(localized: "Turn On “\(record.copy.name)”?"),
            isPresented: $confirmEnable
        ) {
            Button(String(localized: "Turn On")) {
                center.setEnabled(true, id: record.id)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(ExtensionPermissionText.summary(record.permissionFacts))
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

    private var pageTitle: String {
        relation?.title ?? record.copy.name
    }

    private var detailForm: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ExtensionRowIcon(icon: record.manifest.icon, directory: record.directory)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.copy.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(record.copy.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Toggle(isOn: Binding(
                        get: { record.enabled },
                        set: { enabled in
                            if enabled {
                                confirmEnable = true
                            } else {
                                center.setEnabled(false, id: record.id)
                            }
                        }
                    )) {
                        Text(record.copy.name)
                    }
                    .labelsHidden()
                }

                if !dependsOn.isEmpty {
                    relationRow(.dependsOn, count: dependsOn.count)
                }
                if !usedBy.isEmpty {
                    relationRow(.usedBy, count: usedBy.count)
                }
            }

            if record.manifest.providesModel {
                providerSection
            } else if let schema = record.manifest.settings, !schema.orderedKeys.isEmpty {
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

            infoSection
            updateSection

            Section {
                Button(String(localized: "Uninstall"), role: .destructive) {
                    confirmUninstall = true
                }
            }
        }
        .formStyle(.grouped)
    }

    private var providerSection: some View {
        Section {
            ForEach(providers) { provider in
                Button {
                    editor = token(for: provider, isNew: false)
                } label: {
                    HStack(spacing: 8) {
                        Text(provider.listTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if provider.showsModelID {
                            Text(provider.model)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button(String(localized: "New Provider"), action: startNewProvider)
            }
        } header: {
            Text(String(localized: "Providers"))
        }
    }

    private var infoSection: some View {
        Section {
            LabeledContent(String(localized: "Version")) {
                Text(record.manifest.version)
                    .monospacedDigit()
            }
            LabeledContent(String(localized: "Input")) {
                Text(joined(record.copy.inputs))
            }
            LabeledContent(String(localized: "Output")) {
                Text(joined(record.copy.outputs))
            }
            LabeledContent(String(localized: "Local Permission")) {
                Text(String(localized: "None"))
            }
            LabeledContent(String(localized: "Network Permission")) {
                Text(networkPermissionText)
            }
            LabeledContent(String(localized: "Calls")) {
                Text("\(record.invocations)")
                    .monospacedDigit()
            }
        } header: {
            Text(String(localized: "Info"))
        }
    }

    private var updateSection: some View {
        Section {
            Toggle(isOn: autoCheckUpdates) {
                Text(String(localized: "Auto-Check for Updates"))
            }
            LabeledContent(String(localized: "Extension Update")) {
                Button(String(localized: "Check")) {}
                    .disabled(true)
            }
        } header: {
            Text(String(localized: "Updates"))
        }
    }

    private func relationList(_ kind: ExtensionRelation) -> some View {
        let plugins = kind == .dependsOn ? dependsOn : usedBy
        return Form {
            Section {
                ForEach(plugins) { plugin in
                    Button {
                        onOpenPlugin(plugin.id)
                    } label: {
                        HStack(spacing: 12) {
                            ExtensionRowIcon(icon: plugin.manifest.icon, directory: plugin.directory)
                            ExtensionRowCopy(name: plugin.copy.name, summary: plugin.copy.summary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func relationRow(_ kind: ExtensionRelation, count: Int) -> some View {
        Button {
            relation = kind
        } label: {
            HStack(spacing: 8) {
                Text(kind.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dependsOn: [ExtensionRecord] {
        let required = needed(of: record)
        return related(matching: { required.intersection(provides(of: $0)).isEmpty == false })
    }

    private var usedBy: [ExtensionRecord] {
        let offered = provides(of: record)
        return related(matching: { needed(of: $0).intersection(offered).isEmpty == false })
    }

    private func related(matching matches: (ExtensionRecord) -> Bool) -> [ExtensionRecord] {
        center.plugins.filter { other in
            other.id != record.id && matches(other)
        }
    }

    private func needed(of record: ExtensionRecord) -> Set<String> {
        var set = Set(record.manifest.capabilities)
        if record.manifest.rewrite { set.insert("llm") }
        return set
    }

    private func provides(of record: ExtensionRecord) -> Set<String> {
        Set(record.manifest.provides)
    }

    private var networkPermissionText: String {
        var parts = record.manifest.network.hosts
        if record.permissionFacts.allowsConfiguredEndpoint {
            parts.append(String(localized: "Configured endpoint"))
        }
        return joined(parts)
    }

    private func joined(_ items: [String]) -> String {
        let visible = items.filter { !$0.isEmpty }
        if visible.isEmpty { return String(localized: "None") }
        return visible.joined(separator: ", ")
    }

    private var autoCheckUpdates: Binding<Bool> {
        let key = "extension.\(record.id).autoCheckUpdates"
        return Binding(
            get: {
                if UserDefaults.standard.object(forKey: key) == nil { return true }
                return UserDefaults.standard.bool(forKey: key)
            },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }

    private func load() {
        if !record.manifest.providesModel {
            drafts = center.settingsValues(for: record.id)
        }
        reloadProviders()
    }

    private func reloadProviders() {
        providers = center.providers(for: record.id)
    }

    private func goBack() {
        if relation != nil {
            relation = nil
            return
        }
        if !record.manifest.providesModel {
            center.saveSettings(id: record.id, drafts: drafts)
        }
        onBack()
    }

    private func startNewProvider() {
        editor = ProviderEditorToken(
            id: UUID().uuidString,
            isNew: true,
            displayName: "",
            values: blankProviderValues()
        )
    }

    private func token(for provider: ExtensionProvider, isNew: Bool) -> ProviderEditorToken {
        var values = blankProviderValues()
        values["format"] = provider.format
        values["baseURL"] = provider.baseURL
        values["model"] = provider.model
        values["apiKey"] = ""
        return ProviderEditorToken(
            id: provider.id,
            isNew: isNew,
            displayName: provider.displayName,
            values: values
        )
    }

    private func blankProviderValues() -> [String: String] {
        guard let schema = record.manifest.settings else { return [:] }
        var values: [String: String] = [:]
        for key in schema.orderedKeys {
            guard let field = schema.properties[key] else { continue }
            if field.sensitive {
                values[key] = ""
            } else {
                values[key] = field.defaultValue?.stringValue ?? ""
            }
        }
        return values
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

private struct ProviderEditorSheet: View {
    var record: ExtensionRecord
    var token: ProviderEditorToken
    var hasSavedKey: Bool
    var onSave: (ExtensionProvider, String) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var displayName: String
    @State private var values: [String: String]
    @State private var confirmDelete = false

    private static let displayNameKey = "__displayName"

    init(
        record: ExtensionRecord,
        token: ProviderEditorToken,
        hasSavedKey: Bool,
        onSave: @escaping (ExtensionProvider, String) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.record = record
        self.token = token
        self.hasSavedKey = hasSavedKey
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _displayName = State(initialValue: token.displayName)
        _values = State(initialValue: token.values)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(fieldKeys, id: \.self) { key in
                    if key == Self.displayNameKey {
                        TextField(String(localized: "Model Name"), text: $displayName)
                        Text(String(localized: "Optional. Leave blank to show the model name."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let field = record.manifest.settings?.properties[key] {
                        editorField(key: key, field: field)
                    }
                }
                if !token.isNew {
                    Section {
                        Button(String(localized: "Delete Provider"), role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(token.isNew ? String(localized: "New Provider") : record.copy.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(token.isNew ? String(localized: "Add") : String(localized: "Save"), action: save)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 420)
        .confirmationDialog(
            String(localized: "Delete Provider"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive, action: onDelete)
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    private var fieldKeys: [String] {
        var keys = record.manifest.settings?.orderedKeys ?? []
        if let index = keys.firstIndex(of: "model") {
            keys.insert(Self.displayNameKey, at: index + 1)
        } else {
            keys.insert(Self.displayNameKey, at: 0)
        }
        return keys
    }

    private var canSave: Bool {
        let model = (values["model"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (values["apiKey"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !model.isEmpty && (!apiKey.isEmpty || hasSavedKey)
    }

    @ViewBuilder
    private func editorField(key: String, field: ExtensionFieldSchema) -> some View {
        let title = ExtensionCopyResolver.fieldTitle(
            group: "settings",
            key: key,
            field: field,
            strings: record.strings
        )
        if !field.oneOf.isEmpty {
            Picker(title, selection: valueBinding(key)) {
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
            SecureField(title, text: valueBinding(key))
            if hasSavedKey {
                Text(String(localized: "Leave blank to keep the saved key."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            TextField(title, text: valueBinding(key))
            if let summary = ExtensionCopyResolver.fieldSummary(
                group: "settings",
                key: key,
                field: field,
                strings: record.strings
            ), !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func save() {
        let provider = ExtensionProvider(
            id: token.id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            format: values["format"] ?? "",
            baseURL: (values["baseURL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            model: (values["model"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(provider, values["apiKey"] ?? "")
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
