import AiboCore
import AiboIngest
import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ExtensionChoiceOption: Identifiable, Equatable, Sendable {
    var value: String
    var title: String
    var id: String { value }
}

struct ExtensionPromptControl: Identifiable, Equatable, Sendable {
    var key: String
    var title: String
    var kind: Kind
    var choices: [ExtensionChoiceOption]
    var id: String { key }

    enum Kind: Equatable, Sendable {
        case line
        case text
        case menu
        case radio
        case toggle
        case image
    }

    static func kind(for field: ExtensionFieldSchema) -> Kind {
        switch field.control {
        case "line": .line
        case "text": .text
        case "menu": .menu
        case "radio": .radio
        case "switch": .toggle
        case "image": .image
        default:
            if !field.oneOf.isEmpty { .menu }
            else if field.type == "boolean" { .toggle }
            else { .text }
        }
    }
}

struct ExtensionPromptGroup: Identifiable, Equatable, Sendable {
    var controls: [ExtensionPromptControl]
    var id: String { controls.map(\.key).joined(separator: "\u{1f}") }
}

@MainActor
@Observable
final class ExtensionPromptSession {
    let pluginID: String
    let pluginName: String
    let groups: [ExtensionPromptGroup]
    let required: Set<String>
    var values: [String: String]
    var toggles: [String: Bool]
    var phase: Phase = .editing

    enum Phase: Equatable {
        case editing
        /// `message` is the plugin's `status.running` line, or the host fallback.
        case running(message: String)
        case result(summary: String, copyText: String?)
        case failed(message: String, copyText: String)
        /// Plugin-declared warning that is not a missing dependency.
        case notice(summary: String, copyText: String)
        case dependency([ExtensionDependencyIssue])
    }

    init(
        pluginID: String,
        pluginName: String,
        groups: [ExtensionPromptGroup],
        values: [String: String],
        toggles: [String: Bool],
        required: Set<String>
    ) {
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.groups = groups
        self.values = values
        self.toggles = toggles
        self.required = required
    }

    var groupKinds: [[ExtensionPromptControl.Kind]] {
        groups.map { $0.controls.map(\.kind) }
    }

    var canConfirm: Bool {
        for control in groups.flatMap(\.controls) where required.contains(control.key) {
            switch control.kind {
            case .toggle:
                continue
            case .menu, .radio:
                if (values[control.key] ?? "").isEmpty { return false }
            case .text, .line, .image:
                if (values[control.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            }
        }
        return true
    }

    func submissionInput() -> [String: ExtensionValue]? {
        guard canConfirm else { return nil }
        var input: [String: ExtensionValue] = [:]
        for control in groups.flatMap(\.controls) {
            switch control.kind {
            case .toggle:
                input[control.key] = .bool(toggles[control.key] ?? false)
            case .text, .line:
                let raw = ExtensionPromptText.normalized(values[control.key] ?? "", multiline: control.kind == .text)
                input[control.key] = .string(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            case .menu, .radio, .image:
                input[control.key] = .string(values[control.key] ?? "")
            }
        }
        return input
    }

    func chooseImage(for key: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        values[key] = url.path
    }

    /// Clipboard image into the first image field. Text fields keep their own paste.
    @discardableResult
    func pasteImageFromClipboard() -> Bool {
        guard case .editing = phase else { return false }
        guard let key = groups.flatMap(\.controls).first(where: { $0.kind == .image })?.key else { return false }
        return pasteImage(for: key)
    }

    @discardableResult
    func pasteImage(for key: String) -> Bool {
        guard case .editing = phase else { return false }
        guard groups.flatMap(\.controls).contains(where: { $0.key == key && $0.kind == .image }) else { return false }
        guard let url = ExtensionClipboardImage.fileURL() else { return false }
        values[key] = url.path
        return true
    }

    var layoutHeights: [CGFloat] {
        switch phase {
        case .editing:
            [ExtensionBubbleMetrics.promptHeight(kinds: groupKinds)]
        case .running(let message):
            [ExtensionBubbleMetrics.runningCardHeight(text: message)]
        case .result(let summary, _):
            [ExtensionBubbleMetrics.statusHeight(text: summary)]
        case .failed(let message, _):
            [ExtensionBubbleMetrics.statusHeight(text: message)]
        case .notice(let summary, _):
            [ExtensionBubbleMetrics.statusHeight(text: summary)]
        case .dependency(let issues):
            [ExtensionBubbleMetrics.dependencyCardHeight(count: issues.count)]
        }
    }
}

struct ExtensionRecord: Identifiable, Equatable {
    var id: String
    var manifest: ExtensionManifest
    var copy: ExtensionCopy
    var strings: [String: String]
    var enabled: Bool
    var invocations: Int
    var directory: URL

    var permissionFacts: ExtensionPermissionFacts {
        let base = manifest.settings.flatMap { schema in
            schema.properties["baseURL"] != nil
        } ?? false
        return ExtensionPermissionFacts(
            networkHosts: manifest.network.hosts,
            allowsConfiguredEndpoint: manifest.providesModel && base,
            usesModel: manifest.usesModel,
            providesModel: manifest.providesModel
        )
    }
}

/// One configured model endpoint inside the AI provider plugin.
struct ProviderProbeResult: Sendable, Equatable {
    var ok: Bool
    var detail: String
}

struct ExtensionProvider: Identifiable, Equatable {
    var id: String
    var displayName: String
    var format: String
    var baseURL: String
    var model: String

    var listTitle: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var showsModelID: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ExtensionDropOption: Identifiable, Equatable {
    var id: String
    var name: String
    var summary: String
    var icon: ExtensionIcon
    var directory: URL
}

/// Several plugins can open the file that was dropped on the pet.
struct ExtensionFileChoice: Equatable {
    var fileURL: URL
    var options: [ExtensionDropOption]

    var fileName: String { fileURL.lastPathComponent }
}

struct ExtensionPermissionFacts: Equatable {
    var networkHosts: [String]
    var allowsConfiguredEndpoint: Bool
    var usesModel: Bool
    var providesModel: Bool

    var isEmpty: Bool {
        networkHosts.isEmpty && !allowsConfiguredEndpoint && !usesModel && !providesModel
    }
}

@MainActor
@Observable
final class ExtensionCenter {
    static let shared = ExtensionCenter()

    private(set) var plugins: [ExtensionRecord] = []
    private(set) var session: ExtensionPromptSession?
    /// Set when a dropped file matches more than one plugin. The pet shows a picker instead of a prompt.
    private(set) var fileChoice: ExtensionFileChoice?
    private(set) var lastError: String?
    private(set) var isReady = false
    private var store = ExtensionStore.live()
    private var runGeneration = 0

    /// Prompt card, or the drop picker when more than one plugin can open the file.
    var showsPetCard: Bool {
        fileChoice != nil || session != nil
    }

    var layoutHeights: [CGFloat]? {
        guard !ExtensionBubbleWindowController.shared.isDetached else { return nil }
        if let fileChoice {
            return [ExtensionBubbleMetrics.fileChoiceCardHeight(count: fileChoice.options.count)]
        }
        guard let session, !session.layoutHeights.isEmpty else { return nil }
        return session.layoutHeights
    }

    var layoutToken: String {
        if ExtensionBubbleWindowController.shared.isDetached { return "detached" }
        if let fileChoice {
            return "drop-\(fileChoice.options.map(\.id).joined(separator: ","))"
        }
        guard let session else { return "" }
        switch session.phase {
        case .editing:
            return "\(session.pluginID)-editing"
        case .running(let message):
            return "\(session.pluginID)-running-\(message.count)"
        case .result(let summary, _):
            return "\(session.pluginID)-result-\(summary.count)"
        case .failed(let message, _):
            return "\(session.pluginID)-failed-\(message.count)"
        case .notice(let summary, _):
            return "\(session.pluginID)-notice-\(summary.count)"
        case .dependency(let issues):
            return "\(session.pluginID)-dependency-\(issues.map(\.id).joined(separator: ","))"
        }
    }

    var needsKeyWindow: Bool {
        guard !ExtensionBubbleWindowController.shared.isDetached else { return false }
        switch session?.phase {
        case .editing, .dependency:
            return true
        default:
            return false
        }
    }

    var manualPlugins: [ExtensionRecord] {
        plugins.filter { $0.enabled && $0.manifest.hasManualTrigger }
    }

    private init() {}

    func start() {
        reload()
        isReady = true
        ExtensionLinkRouter.deliver()
    }

    /// Manual plugins open their prompt bubble. Anything else opens Settings.
    func openLinkedPlugin(slug: String) {
        guard let record = plugins.first(where: { $0.manifest.slug == slug }) else { return }
        if record.enabled, record.manifest.hasManualTrigger {
            AiboPanelController.shared.show()
            beginManualPrompt(id: record.id)
            return
        }
        SettingsNavigator.shared.openExtension(id: record.id)
    }

    func reload() {
        let registry = store.loadRegistry()
        plugins = store.installed().map { package in
            let strings = store.loadLocaleStrings(
                in: package.directory,
                localization: package.manifest.localization
            )
            return ExtensionRecord(
                id: package.manifest.id,
                manifest: package.manifest,
                copy: ExtensionCopyResolver.resolve(manifest: package.manifest, strings: strings),
                strings: strings,
                enabled: registry.isEnabled(package.manifest.id),
                invocations: registry.invocations(for: package.manifest.id),
                directory: package.directory
            )
        }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        var registry = store.loadRegistry()
        if enabled {
            if !registry.enabledIDs.contains(id) {
                registry.enabledIDs.append(id)
            }
        } else {
            registry.enabledIDs.removeAll { $0 == id }
            if session?.pluginID == id {
                cancelSession()
            }
        }
        try? store.saveRegistry(registry)
        reload()
    }

    func noteInstallFailure(_ message: String) {
        lastError = message
    }

    func install(from directory: URL) {
        do {
            _ = try store.install(from: directory)
            lastError = nil
            reload()
        } catch let error as ExtensionStoreError {
            lastError = Self.installMessage(for: error)
        } catch {
            lastError = String(localized: "Couldn't install the plugin.")
        }
    }

    private static func installMessage(for error: ExtensionStoreError) -> String {
        guard case .blocked(let block) = error else {
            return String(localized: "Couldn't install the plugin.")
        }
        var parts: [String] = []
        let missing = block.missingCapabilities
        if missing.count == 1, let name = missing.first {
            parts.append(String(localized: "Install a plugin that provides “\(name)” first."))
        } else if missing.count > 1 {
            let list = ListFormatter.localizedString(byJoining: missing.map { "“\($0)”" })
            parts.append(String(localized: "Install plugins that provide \(list) first."))
        }
        if let slug = block.duplicateSlug {
            parts.append(String(localized: "Another plugin is already using the link “\(slug)”."))
        }
        if parts.isEmpty {
            return String(localized: "Couldn't install the plugin.")
        }
        return parts.joined(separator: "\n")
    }

    func uninstall(id: String) {
        if session?.pluginID == id {
            cancelSession()
        }
        let record = plugins.first { $0.id == id }
        for provider in providers(for: id) {
            KeychainStore.delete(account: providerKeychainAccount(pluginID: id, providerID: provider.id))
        }
        for key in store.sensitiveKeys(in: record?.manifest.settings) {
            KeychainStore.delete(account: keychainAccount(id: id, key: key))
        }
        try? store.uninstall(id: id)
        reload()
    }

    func settingsValues(for id: String) -> [String: String] {
        guard let record = plugins.first(where: { $0.id == id }) else { return [:] }
        let saved = store.loadSettings(id: id)
        var values: [String: String] = [:]
        for key in record.manifest.settings?.orderedKeys ?? [] {
            guard let field = record.manifest.settings?.properties[key] else { continue }
            if field.sensitive {
                values[key] = ""
                continue
            }
            if let stored = saved[key]?.stringValue {
                values[key] = stored
            } else if let fallback = field.defaultValue?.stringValue {
                values[key] = fallback
            } else {
                values[key] = ""
            }
        }
        return values
    }

    func hasSavedSecret(id: String, key: String) -> Bool {
        KeychainStore.string(forAccount: keychainAccount(id: id, key: key))?.isEmpty == false
    }

    func saveSettings(id: String, drafts: [String: String]) {
        guard let record = plugins.first(where: { $0.id == id }),
              let schema = record.manifest.settings
        else { return }
        var stored = store.loadSettings(id: id)
        for key in schema.orderedKeys {
            guard let field = schema.properties[key] else { continue }
            let draft = drafts[key] ?? ""
            if field.sensitive {
                if !draft.isEmpty {
                    try? KeychainStore.setString(draft, forAccount: keychainAccount(id: id, key: key))
                }
            } else {
                stored[key] = .string(draft)
            }
        }
        try? store.saveSettings(id: id, values: stored)
    }

    func providers(for pluginID: String) -> [ExtensionProvider] {
        migrateLegacyProviderIfNeeded(pluginID: pluginID)
        return decodeProviders(store.loadSettings(id: pluginID))
    }

    func providerHasSecret(pluginID: String, providerID: String) -> Bool {
        let secret = KeychainStore.string(
            forAccount: providerKeychainAccount(pluginID: pluginID, providerID: providerID)
        )
        return secret?.isEmpty == false
    }

    func saveProvider(pluginID: String, provider: ExtensionProvider, apiKeyDraft: String) {
        var list = providers(for: pluginID)
        if let index = list.firstIndex(where: { $0.id == provider.id }) {
            list[index] = provider
        } else {
            list.append(provider)
        }
        let draft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            try? KeychainStore.setString(
                draft,
                forAccount: providerKeychainAccount(pluginID: pluginID, providerID: provider.id)
            )
        }
        writeProviders(pluginID: pluginID, list)
    }

    /// One short completion against the draft provider. Does not save it.
    func probeProvider(
        pluginID: String,
        providerID: String,
        format: String,
        baseURL: String,
        model: String,
        apiKeyDraft: String
    ) async -> ProviderProbeResult {
        let draft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if !draft.isEmpty {
            apiKey = draft
        } else if let saved = KeychainStore.string(
            forAccount: providerKeychainAccount(pluginID: pluginID, providerID: providerID)
        ), !saved.isEmpty {
            apiKey = saved
        } else {
            return ProviderProbeResult(ok: false, detail: "")
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            return ProviderProbeResult(ok: false, detail: "")
        }
        guard let params = ProviderProbe.request(
            format: format,
            baseURL: baseURL,
            model: trimmedModel,
            apiKey: apiKey
        ) else {
            return ProviderProbeResult(ok: false, detail: String(localized: "Check the base URL."))
        }
        guard let url = params["url"]?.stringValue,
              let host = ExtensionURLPolicy.host(ofURLString: url)
        else {
            return ProviderProbeResult(ok: false, detail: String(localized: "Check the base URL."))
        }
        let response = await ExtensionFetch.perform(params: params, allowedHosts: [host])
        if let message = response["error"]?.objectValue?["message"]?.stringValue {
            return ProviderProbeResult(ok: false, detail: ProviderProbe.localMessage(for: message))
        }
        let status: Int
        if let statusValue = response["status"], case .number(let value) = statusValue {
            status = Int(value)
        } else {
            status = 0
        }
        let body = response["body"]?.stringValue ?? ""
        if let message = ProviderProbe.apiErrorMessage(in: body) {
            return ProviderProbeResult(ok: false, detail: redact(message, secrets: [apiKey]))
        }
        if (200..<300).contains(status) {
            return ProviderProbeResult(ok: true, detail: "")
        }
        if status > 0 {
            return ProviderProbeResult(ok: false, detail: "HTTP \(status)")
        }
        return ProviderProbeResult(ok: false, detail: "")
    }

    func deleteProvider(pluginID: String, providerID: String) {
        var list = providers(for: pluginID)
        list.removeAll { $0.id == providerID }
        KeychainStore.delete(account: providerKeychainAccount(pluginID: pluginID, providerID: providerID))
        writeProviders(pluginID: pluginID, list)
    }

    func beginManualPrompt(id: String, fileURL: URL? = nil) {
        fileChoice = nil
        guard let record = plugins.first(where: { $0.id == id }),
              record.enabled,
              record.manifest.hasManualTrigger
        else { return }
        if fileURL == nil, case .running = session?.phase, session?.pluginID == id {
            return
        }
        if fileURL != nil {
            runGeneration += 1
        }
        var form = promptForm(for: record)
        if let fileURL {
            prefillImage(fileURL, into: &form, manifest: record.manifest)
        }
        AiboPanelController.shared.discardPluginColumnSlot()
        session = ExtensionPromptSession(
            pluginID: record.id,
            pluginName: record.copy.name,
            groups: form.groups,
            values: form.values,
            toggles: form.toggles,
            required: form.required
        )
        applyDependencyGate()
        if fileURL != nil, case .editing = session?.phase, session?.canConfirm == true {
            confirmPrompt()
        }
        let needsCatalog = !record.manifest.requiredCapabilities.isEmpty
            && ExtensionCatalogClient.shared.entries.isEmpty
        guard needsCatalog else { return }
        Task {
            await ExtensionCatalogClient.shared.reload()
            guard self.session?.pluginID == id else { return }
            applyDependencyGate()
        }
    }

    /// Dropped on the pet. One matching plugin opens with the file filled in.
    /// Several matching plugins show a picker first.
    func receiveDroppedFile(_ url: URL) {
        let options = dropOptions(for: url)
        guard !options.isEmpty else { return }
        AiboPanelController.shared.show()
        if options.count == 1, let only = options.first {
            beginManualPrompt(id: only.id, fileURL: url)
            return
        }
        AiboPanelController.shared.discardPluginColumnSlot()
        runGeneration += 1
        if ExtensionBubbleWindowController.shared.isDetached {
            ExtensionBubbleWindowController.shared.dismiss()
        }
        session = nil
        fileChoice = ExtensionFileChoice(fileURL: url, options: options)
        publishLayout()
    }

    func canAcceptDroppedFile(_ url: URL) -> Bool {
        !dropOptions(for: url).isEmpty
    }

    func chooseDroppedPlugin(id: String) {
        guard let fileChoice, fileChoice.options.contains(where: { $0.id == id }) else { return }
        let url = fileChoice.fileURL
        beginManualPrompt(id: id, fileURL: url)
    }

    func cancelFileChoice() {
        guard fileChoice != nil else { return }
        let detached = ExtensionBubbleWindowController.shared.isDetached
        if !detached {
            AiboPanelController.shared.beginPluginPoofHoldIfNeeded()
        }
        withAnimation(detached ? nil : BubbleMotion.disappear) {
            fileChoice = nil
        }
        publishLayout()
        AiboPanelController.shared.clearExtensionCardFrame()
    }

    func confirmPrompt() {
        guard let session, case .editing = session.phase else { return }
        guard let input = session.submissionInput() else { return }
        let pluginID = session.pluginID
        session.phase = .running(message: runningStatus(for: pluginID))
        runGeneration += 1
        let generation = runGeneration
        publishLayout()
        Task {
            let outcome = await run(id: pluginID, trigger: "manual", input: input, depth: 0)
            guard generation == runGeneration, self.session?.pluginID == pluginID else { return }
            present(outcome)
            publishLayout()
        }
    }

    func installDependency(catalogID: String) {
        Task {
            await ExtensionCatalogClient.shared.install(id: catalogID)
            applyDependencyGate()
        }
    }

    func setDependencyEnabled(_ enabled: Bool, pluginID: String) {
        setEnabled(enabled, id: pluginID)
        applyDependencyGate()
    }

    func copyResult() {
        guard let text = copyPayload(), !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func cancelSession() {
        guard session != nil else { return }
        runGeneration += 1
        let detached = ExtensionBubbleWindowController.shared.isDetached
        // Hold the side row, then remove the card so its transition can poof
        // without the pet following the collapse. A detached card is already
        // off the pet, so there is nothing to hold.
        if !detached {
            AiboPanelController.shared.beginPluginPoofHoldIfNeeded()
        }
        withAnimation(detached ? nil : BubbleMotion.disappear) {
            session = nil
        }
        ExtensionBubbleWindowController.shared.dismiss()
        publishLayout()
        AiboPanelController.shared.clearExtensionCardFrame()
    }

    #if DEBUG
    /// Sample plugin window for layout checks. Does not run the plugin.
    func presentDebugWindow(running: Bool) {
        fileChoice = nil
        runGeneration += 1
        let record = plugins.first { $0.manifest.slug == "translate" }
            ?? plugins.first { $0.manifest.hasManualTrigger }
        let pluginID = record?.id ?? "debug.extension-window"
        let session = ExtensionPromptSession(
            pluginID: pluginID,
            pluginName: record?.copy.name ?? "Translate",
            groups: [],
            values: [:],
            toggles: [:],
            required: []
        )
        if running {
            session.phase = .running(message: runningStatus(for: pluginID))
        } else {
            let summary = "The world is so big."
            session.phase = .result(summary: summary, copyText: summary)
        }
        self.session = session
        ExtensionBubbleWindowController.shared.detach()
    }
    #endif

    private func present(_ outcome: RunOutcome) {
        switch outcome {
        case .bubbles(let bubbles):
            guard let bubble = bubbles.first else {
                let message = String(localized: "Plugin failed")
                session?.phase = .failed(message: message, copyText: message)
                return
            }
            let summary = bubble.summary
            let copyText = bubble.actions.first { $0.copyText != nil }?.copyText ?? summary
            switch bubble.outcome {
            case .success:
                session?.phase = .result(summary: summary, copyText: copyText)
            case .failure:
                session?.phase = .failed(message: summary, copyText: copyText)
            case .warning:
                session?.phase = .notice(summary: summary, copyText: copyText)
            }
        case .failed(let message):
            session?.phase = .failed(message: message, copyText: message)
        }
    }

    private func runningStatus(for pluginID: String) -> String {
        let custom = plugins.first { $0.id == pluginID }?.strings["status.running"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return String(localized: "Working…")
    }

    private func applyDependencyGate() {
        guard let session else { return }
        switch session.phase {
        case .editing, .dependency:
            break
        default:
            return
        }
        let issues = dependencyIssues(for: session.pluginID)
        if issues.isEmpty {
            if case .dependency = session.phase {
                session.phase = .editing
            }
        } else {
            session.phase = .dependency(issues)
        }
        publishLayout()
    }

    private func dependencyIssues(for pluginID: String) -> [ExtensionDependencyIssue] {
        guard let record = plugins.first(where: { $0.id == pluginID }) else { return [] }
        let installed = plugins.filter { $0.id != pluginID }.map { plugin in
            ExtensionDependencyGate.Installed(
                id: plugin.id,
                name: plugin.copy.name,
                summary: plugin.copy.summary,
                provides: plugin.manifest.provides,
                enabled: plugin.enabled
            )
        }
        let language = Locale.preferredLanguages.first ?? "en"
        let catalog = ExtensionCatalogClient.shared.entries.map { entry in
            let copy = entry.displayCopy(preferredLanguage: language)
            return ExtensionDependencyGate.Listed(
                id: entry.id,
                name: copy.name,
                summary: copy.summary,
                provides: entry.provides
            )
        }
        return ExtensionDependencyGate.issues(
            required: record.manifest.requiredCapabilities,
            installed: installed,
            catalog: catalog
        )
    }

    private func copyPayload() -> String? {
        guard let session else { return nil }
        switch session.phase {
        case .result(_, let copyText):
            return copyText
        case .failed(_, let copyText), .notice(_, let copyText):
            return copyText
        case .dependency(let issues):
            return dependencyReport(pluginName: session.pluginName, issues: issues)
        case .editing, .running:
            return nil
        }
    }

    private func dependencyReport(pluginName: String, issues: [ExtensionDependencyIssue]) -> String {
        issues.map { issue in
            let need = String(localized: "\(pluginName) needs a plugin that provides “\(issue.capability)”.")
            let state: String = switch issue.remedy {
            case .install:
                String(localized: "\(issue.name) is not installed.")
            case .enable:
                String(localized: "\(issue.name) is turned off.")
            case .unavailable:
                String(localized: "No plugin provides “\(issue.capability)”.")
            }
            return [need, state, issue.summary].filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func publishLayout() {
        AiboPanelController.shared.refreshContent()
        AiboPanelController.shared.updateOnboardingKeyWindow()
    }

    private struct PromptForm {
        var groups: [ExtensionPromptGroup]
        var values: [String: String]
        var toggles: [String: Bool]
        var required: Set<String>
    }

    private func prefillImage(_ url: URL, into form: inout PromptForm, manifest: ExtensionManifest) {
        guard let schema = manifest.prompt else { return }
        guard let key = schema.orderedKeys.first(where: { schema.properties[$0]?.control == "image" }) else {
            return
        }
        form.values[key] = url.path
    }

    private func dropOptions(for url: URL) -> [ExtensionDropOption] {
        plugins.compactMap { record in
            guard record.enabled, record.manifest.hasManualTrigger else { return nil }
            guard ExtensionFileAcceptance.matches(url: url, accepts: record.manifest.accepts) else { return nil }
            return ExtensionDropOption(
                id: record.id,
                name: record.copy.name,
                summary: record.copy.summary,
                icon: record.manifest.icon,
                directory: record.directory
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Paths the user put in image fields. Only these may be read for the model.
    private static func imagePaths(in input: [String: ExtensionValue], manifest: ExtensionManifest) -> Set<String> {
        guard let schema = manifest.prompt else { return [] }
        var paths: Set<String> = []
        for (key, field) in schema.properties where field.control == "image" {
            let path = input[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty { paths.insert(path) }
        }
        return paths
    }

    private static func imageMessage(_ failure: ExtensionImageInline.Failure) -> String {
        switch failure {
        case .tooLarge:
            String(localized: "This image is too large.")
        case .unsupportedType:
            String(localized: "Use a PNG or JPEG image.")
        case .unreadable:
            String(localized: "Couldn't read the image.")
        }
    }

    private func promptForm(for record: ExtensionRecord) -> PromptForm {
        guard let schema = record.manifest.prompt, !schema.properties.isEmpty else {
            return fallbackPrompt()
        }
        var values: [String: String] = [:]
        var toggles: [String: Bool] = [:]
        let groups = schema.fieldGroups().compactMap { keys -> ExtensionPromptGroup? in
            let controls = keys.compactMap { key -> ExtensionPromptControl? in
                guard let field = schema.properties[key] else { return nil }
                let control = ExtensionPromptControl(
                    key: key,
                    title: ExtensionCopyResolver.fieldTitle(
                        group: "prompt",
                        key: key,
                        field: field,
                        strings: record.strings
                    ),
                    kind: ExtensionPromptControl.kind(for: field),
                    choices: field.oneOf.map { choice in
                        ExtensionChoiceOption(
                            value: choice.value,
                            title: ExtensionCopyResolver.choiceTitle(
                                group: "prompt",
                                key: key,
                                choice: choice,
                                strings: record.strings
                            )
                        )
                    }
                )
                switch control.kind {
                case .toggle:
                    toggles[key] = boolDefault(field.defaultValue)
                case .menu, .radio:
                    values[key] = field.defaultValue?.stringValue ?? control.choices.first?.value ?? ""
                case .text, .line, .image:
                    values[key] = field.defaultValue?.stringValue ?? ""
                }
                return control
            }
            guard !controls.isEmpty else { return nil }
            return ExtensionPromptGroup(controls: controls)
        }
        return PromptForm(
            groups: groups,
            values: values,
            toggles: toggles,
            required: Set(schema.required)
        )
    }

    private func fallbackPrompt() -> PromptForm {
        let text = ExtensionPromptControl(
            key: "text",
            title: String(localized: "Text to translate"),
            kind: .text,
            choices: []
        )
        let target = ExtensionPromptControl(
            key: "target",
            title: String(localized: "Target language"),
            kind: .menu,
            choices: [
                ExtensionChoiceOption(value: "zh-Hans", title: "简体中文"),
                ExtensionChoiceOption(value: "en", title: "English"),
                ExtensionChoiceOption(value: "ja", title: "日本語"),
            ]
        )
        return PromptForm(
            groups: [
                ExtensionPromptGroup(controls: [text]),
                ExtensionPromptGroup(controls: [target]),
            ],
            values: ["text": "", "target": "en"],
            toggles: [:],
            required: ["text"]
        )
    }

    private func boolDefault(_ value: ExtensionValue?) -> Bool {
        if case .bool(let flag) = value { return flag }
        return false
    }

    private enum RunOutcome {
        case bubbles([ExtensionBubbleContent])
        case failed(String)
    }

    private func run(
        id: String,
        trigger: String,
        input: [String: ExtensionValue],
        depth: Int
    ) async -> RunOutcome {
        guard let record = plugins.first(where: { $0.id == id }), record.enabled else {
            return .failed(String(localized: "Plugin failed"))
        }
        guard let source = try? String(contentsOf: record.directory.appendingPathComponent(record.manifest.entry), encoding: .utf8) else {
            return .failed(String(localized: "Plugin failed"))
        }
        incrementInvocations(id: id)
        let settings = runtimeSettings(for: record)
        let secrets = secretValues(for: record)
        let generation = runGeneration
        var responses: [String: ExtensionValue] = [:]
        var requestState = ""
        for _ in 0..<6 {
            if generation != runGeneration {
                return .failed(String(localized: "Plugin failed"))
            }
            var parameters = runParameters(
                record: record,
                trigger: trigger,
                settings: settings,
                input: input,
                requestState: requestState,
                responses: responses
            )
            let round: ExtensionRoundResult
            do {
                round = try await ExtensionJavaScript.invoke(source: source, parameters: parameters)
            } catch {
                return .failed(String(localized: "Plugin failed"))
            }
            switch round {
            case .complete(let completion):
                if depth > 0 {
                    return .bubbles([])
                }
                if completion.content.isEmpty, let message = completion.output["error"]?.objectValue?["message"]?.stringValue {
                    return .failed(redact(message, secrets: secrets))
                }
                let bubbles = completion.content.map { bubble in
                    ExtensionBubbleContent(
                        outcome: bubble.outcome,
                        status: bubble.status,
                        summary: redact(bubble.summary, secrets: secrets),
                        actions: bubble.actions.map { action in
                            ExtensionBubbleAction(
                                title: action.title,
                                copyText: action.copyText.map { redact($0, secrets: secrets) },
                                open: action.open
                            )
                        }
                    )
                }
                if bubbles.isEmpty {
                    return .failed(String(localized: "Plugin failed"))
                }
                return .bubbles(bubbles)
            case .inputRequired(let requests, let state):
                requestState = state
                var next: [String: ExtensionValue] = [:]
                let allowedImagePaths = Self.imagePaths(in: input, manifest: record.manifest)
                for (key, request) in requests {
                    next[key] = await fulfill(
                        request,
                        caller: record,
                        depth: depth,
                        allowedImagePaths: allowedImagePaths
                    )
                }
                responses = next
                if depth > 0, requests.values.contains(where: { $0.method == "aibo/llm" }) {
                    return .failed(String(localized: "Plugin failed"))
                }
                if depth > 0 {
                    let providerDone = next.values.allSatisfy { value in
                        value.objectValue?["text"] != nil || value.objectValue?["error"] != nil
                    }
                    if requests.values.allSatisfy({ $0.method == "aibo/fetch" }) == false && providerDone {
                        return .bubbles([])
                    }
                }
            }
        }
        return .failed(String(localized: "Plugin failed"))
    }

    /// Nested provider runs return their `output` object through `aibo/llm`, not a bubble.
    private func fulfill(
        _ request: ExtensionInputRequest,
        caller: ExtensionRecord,
        depth: Int,
        allowedImagePaths: Set<String>
    ) async -> ExtensionValue {
        switch request.method {
        case "aibo/llm":
            guard depth == 0 else {
                return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
            }
            let params: [String: ExtensionValue]
            switch ExtensionImageInline.attach(params: request.params, allowedPaths: allowedImagePaths) {
            case .success(let attached):
                params = attached
            case .failure(let failure):
                return .object(["error": .object(["message": .string(Self.imageMessage(failure))])])
            }
            let models = modelOfferings(capability: "llm")
            let saved = savedCapabilitySelection(for: caller, capability: "llm")
            guard let model = ExtensionModelExport.resolve(saved: saved, models: models) else {
                if plugins.contains(where: { $0.enabled && $0.manifest.providesModel }) {
                    return .object(["error": .object(["message": .string(String(localized: "Add a provider in AI Provider."))])])
                }
                return .object(["error": .object(["message": .string(String(localized: "The AI provider plugin is off."))])])
            }
            guard let plugin = plugins.first(where: { $0.id == model.pluginID }), plugin.enabled else {
                return .object(["error": .object(["message": .string(String(localized: "The AI provider plugin is off."))])])
            }
            return await providerOutput(id: plugin.id, providerID: model.providerID, params: params)
        case "aibo/fetch":
            let hosts = allowedHosts(for: caller)
            let response = await ExtensionFetch.perform(params: request.params, allowedHosts: hosts)
            return .object(response)
        default:
            return .object(["error": .object(["message": .string("Unsupported request")])])
        }
    }

    private func providerOutput(id: String, providerID: String, params: [String: ExtensionValue]) async -> ExtensionValue {
        guard let record = plugins.first(where: { $0.id == id }) else {
            return .object(["error": .object(["message": .string(String(localized: "The AI provider plugin is off."))])])
        }
        guard let source = try? String(contentsOf: record.directory.appendingPathComponent(record.manifest.entry), encoding: .utf8) else {
            return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
        }
        incrementInvocations(id: id)
        let settings = runtimeSettings(for: record, providerID: providerID)
        let generation = runGeneration
        var responses: [String: ExtensionValue] = [:]
        var requestState = ""
        for _ in 0..<4 {
            if generation != runGeneration {
                return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
            }
            let parameters = runParameters(
                record: record,
                trigger: "llm",
                settings: settings,
                input: params,
                requestState: requestState,
                responses: responses
            )
            let round: ExtensionRoundResult
            do {
                round = try await ExtensionJavaScript.invoke(source: source, parameters: parameters)
            } catch {
                return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
            }
            switch round {
            case .complete(let completion):
                if let message = completion.output["error"]?.objectValue?["message"]?.stringValue {
                    let secrets = secretValues(for: record)
                    return .object(["error": .object(["message": .string(redact(message, secrets: secrets))])])
                }
                return .object(completion.output)
            case .inputRequired(let requests, let state):
                requestState = state
                var next: [String: ExtensionValue] = [:]
                for (key, request) in requests {
                    if request.method == "aibo/llm" {
                        next[key] = .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
                    } else {
                        next[key] = await fulfill(request, caller: record, depth: 1, allowedImagePaths: [])
                    }
                }
                responses = next
            }
        }
        return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
    }

    private func runParameters(
        record: ExtensionRecord,
        trigger: String,
        settings: [String: ExtensionValue],
        input: [String: ExtensionValue],
        requestState: String,
        responses: [String: ExtensionValue]
    ) -> [String: ExtensionValue] {
        var parameters: [String: ExtensionValue] = [
            "trigger": .string(trigger),
            "settings": .object(settings),
            "input": .object(input),
            "requestState": .string(requestState),
            "locale": .string(Locale.preferredLanguages.first ?? "en"),
        ]
        if !responses.isEmpty {
            parameters["inputResponses"] = .object(responses)
        }
        let provided = providedParameters(for: record)
        if !provided.isEmpty {
            parameters["provided"] = .object(provided)
        }
        return parameters
    }

    /// Configured models published by plugins that `provide` this capability.
    /// Enabled plugins come first so the default selection is one that can run.
    func modelOfferings(capability: String) -> [ExtensionProvidedModel] {
        let matching = plugins.filter { $0.manifest.provides.contains(capability) }
        let ordered = matching.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled && !rhs.enabled }
            return lhs.id < rhs.id
        }
        return ordered.flatMap { record in
            let declared = record.manifest.exports.first { $0.capability == capability }?.fields ?? []
            guard !declared.isEmpty else { return [ExtensionProvidedModel]() }
            let sensitive = Set(
                record.manifest.settings?.properties.compactMap { key, field in
                    field.sensitive ? key : nil
                } ?? []
            )
            let records = providers(for: record.id).map { provider in
                ExtensionProviderRecord(
                    id: provider.id,
                    displayName: provider.displayName,
                    values: [
                        "format": provider.format,
                        "baseURL": provider.baseURL,
                        "model": provider.model,
                    ]
                )
            }
            return ExtensionModelExport.models(
                pluginID: record.id,
                declaredFields: declared,
                providers: records,
                sensitiveKeys: sensitive
            )
        }
    }

    private func allowedHosts(for record: ExtensionRecord) -> Set<String> {
        var hosts = Set(record.manifest.network.hosts.map { $0.lowercased() })
        let settings = runtimeSettings(for: record)
        if let base = settings["baseURL"]?.stringValue, let host = ExtensionURLPolicy.host(ofURLString: base) {
            hosts.insert(host)
        }
        for provider in providers(for: record.id) {
            if let host = ExtensionURLPolicy.host(ofURLString: provider.baseURL) {
                hosts.insert(host.lowercased())
            }
        }
        if record.manifest.providesModel {
            hosts.insert("generativelanguage.googleapis.com")
            hosts.insert("api.openai.com")
        }
        return hosts
    }

    private func runtimeSettings(for record: ExtensionRecord, providerID: String? = nil) -> [String: ExtensionValue] {
        var values = store.loadSettings(id: record.id)
        if let schema = record.manifest.settings {
            for key in schema.orderedKeys {
                guard let field = schema.properties[key] else { continue }
                if field.sensitive {
                    if let secret = KeychainStore.string(forAccount: keychainAccount(id: record.id, key: key)), !secret.isEmpty {
                        values[key] = .string(secret)
                    }
                } else if values[key] == nil, let fallback = field.defaultValue {
                    values[key] = fallback
                }
            }
        }
        let list = providers(for: record.id)
        let provider: ExtensionProvider?
        if let providerID {
            provider = list.first { $0.id == providerID }
        } else {
            provider = list.first
        }
        if let provider {
            values["format"] = .string(provider.format)
            values["baseURL"] = .string(provider.baseURL)
            values["model"] = .string(provider.model)
            if let secret = KeychainStore.string(
                forAccount: providerKeychainAccount(pluginID: record.id, providerID: provider.id)
            ), !secret.isEmpty {
                values["apiKey"] = .string(secret)
            }
        }
        return values
    }

    /// `params.provided.<capability>` for a dependent plugin: the selected model and each exported field.
    private func providedParameters(for record: ExtensionRecord) -> [String: ExtensionValue] {
        var object: [String: ExtensionValue] = [:]
        for capability in record.manifest.requiredCapabilities {
            let models = modelOfferings(capability: capability)
            guard !models.isEmpty || record.manifest.settings?.properties.values.contains(where: { $0.source == capability }) == true else {
                continue
            }
            let selected = ExtensionModelExport.resolve(
                saved: savedCapabilitySelection(for: record, capability: capability),
                models: models
            )
            object[capability] = .object([
                "selected": .string(selected?.id ?? ""),
                "models": .array(models.map(providedModelValue)),
            ])
        }
        return object
    }

    private func providedModelValue(_ model: ExtensionProvidedModel) -> ExtensionValue {
        .object([
            "id": .string(model.id),
            "title": .string(model.title),
            "fields": .object(model.fields.mapValues { .string($0) }),
        ])
    }

    private func savedCapabilitySelection(for record: ExtensionRecord, capability: String) -> String? {
        guard let schema = record.manifest.settings else { return nil }
        guard let key = schema.orderedKeys.first(where: { schema.properties[$0]?.source == capability }) else {
            return nil
        }
        let saved = store.loadSettings(id: record.id)[key]?.stringValue ?? ""
        return saved.isEmpty ? nil : saved
    }

    private func secretValues(for record: ExtensionRecord) -> [String] {
        var secrets: [String] = []
        if let schema = record.manifest.settings {
            for (key, field) in schema.properties where field.sensitive {
                if let secret = KeychainStore.string(forAccount: keychainAccount(id: record.id, key: key)), !secret.isEmpty {
                    secrets.append(secret)
                }
            }
        }
        for provider in providers(for: record.id) {
            if let secret = KeychainStore.string(
                forAccount: providerKeychainAccount(pluginID: record.id, providerID: provider.id)
            ), !secret.isEmpty {
                secrets.append(secret)
            }
        }
        return secrets
    }

    private func incrementInvocations(id: String) {
        var registry = store.loadRegistry()
        registry.invocationCounts[id, default: 0] += 1
        try? store.saveRegistry(registry)
        reload()
    }

    private func keychainAccount(id: String, key: String) -> String {
        "extension.\(id).\(key)"
    }

    private func providerKeychainAccount(pluginID: String, providerID: String) -> String {
        "extension.\(pluginID).provider.\(providerID).apiKey"
    }

    private func decodeProviders(_ stored: [String: ExtensionValue]) -> [ExtensionProvider] {
        guard case .array(let items) = stored["providers"] else { return [] }
        return items.compactMap { item in
            guard case .object(let object) = item,
                  let id = object["id"]?.stringValue,
                  !id.isEmpty
            else { return nil }
            return ExtensionProvider(
                id: id,
                displayName: object["displayName"]?.stringValue ?? "",
                format: object["format"]?.stringValue ?? "",
                baseURL: object["baseURL"]?.stringValue ?? "",
                model: object["model"]?.stringValue ?? ""
            )
        }
    }

    /// Older installs stored one provider as flat settings keys. Fold that into the list once.
    private func migrateLegacyProviderIfNeeded(pluginID: String) {
        let stored = store.loadSettings(id: pluginID)
        if stored["providers"] != nil { return }
        let format = stored["format"]?.stringValue ?? ""
        let baseURL = stored["baseURL"]?.stringValue ?? ""
        let model = stored["model"]?.stringValue ?? ""
        let legacyAccount = keychainAccount(id: pluginID, key: "apiKey")
        let legacyKey = KeychainStore.string(forAccount: legacyAccount) ?? ""
        let hasAnything = !format.isEmpty || !baseURL.isEmpty || !model.isEmpty || !legacyKey.isEmpty
        guard hasAnything else { return }
        let providerID = UUID().uuidString
        if !legacyKey.isEmpty {
            try? KeychainStore.setString(
                legacyKey,
                forAccount: providerKeychainAccount(pluginID: pluginID, providerID: providerID)
            )
            KeychainStore.delete(account: legacyAccount)
        }
        writeProviders(
            pluginID: pluginID,
            [
                ExtensionProvider(
                    id: providerID,
                    displayName: "",
                    format: format,
                    baseURL: baseURL,
                    model: model
                ),
            ]
        )
    }

    private func writeProviders(pluginID: String, _ list: [ExtensionProvider]) {
        let array = list.map { provider in
            ExtensionValue.object([
                "id": .string(provider.id),
                "displayName": .string(provider.displayName),
                "format": .string(provider.format),
                "baseURL": .string(provider.baseURL),
                "model": .string(provider.model),
            ])
        }
        try? store.saveSettings(id: pluginID, values: ["providers": .array(array)])
    }

    private func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where secret.count >= 4 {
            result = result.replacingOccurrences(of: secret, with: "‹redacted›")
        }
        if result.count > 2000 {
            return String(result.prefix(2000))
        }
        return result
    }
}

/// Stock hosts for the AI provider formats. An empty base URL, or the other format's stock host,
/// is rewritten so the field shows the address the request will actually use. A host the user typed stays.
enum ProviderAPIDefaults {
    static let openAIBase = "https://api.openai.com/v1"
    static let googleBase = "https://generativelanguage.googleapis.com/v1beta"

    static func displayBase(format: String, baseURL: String) -> String {
        let current = stripped(baseURL)
        switch format {
        case "google-interactions":
            if current.isEmpty || current == openAIBase { return googleBase }
            return current
        case "chat-completions":
            if current.isEmpty || current == googleBase { return openAIBase }
            return current
        default:
            return current
        }
    }

    static func stripped(_ baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }
}

/// Builds the same request the AI provider plugin sends, then reads a pass or fail.
private enum ProviderProbe {

    static func request(
        format: String,
        baseURL: String,
        model: String,
        apiKey: String
    ) -> [String: ExtensionValue]? {
        let resolved = resolvedBase(format: format, baseURL: baseURL)
        let url: String
        let headers: [String: ExtensionValue]
        let payload: [String: Any]
        if format == "google-interactions" {
            url = join(resolved, "/interactions")
            headers = [
                "Content-Type": .string("application/json"),
                "x-goog-api-key": .string(apiKey),
            ]
            payload = [
                "model": model,
                "input": "Hi",
                "system_instruction": "",
                "store": false,
            ]
        } else {
            url = chatURL(resolved)
            headers = [
                "Content-Type": .string("application/json"),
                "Authorization": .string("Bearer \(apiKey)"),
            ]
            payload = [
                "model": model,
                "messages": [["role": "user", "content": "Hi"]],
                "max_tokens": 16,
            ]
        }
        guard let body = jsonString(payload), ExtensionURLPolicy.host(ofURLString: url) != nil else {
            return nil
        }
        return [
            "url": .string(url),
            "method": .string("POST"),
            "headers": .object(headers),
            "body": .string(body),
        ]
    }

    static func localMessage(for code: String) -> String {
        switch code {
        case "https-only":
            String(localized: "Use an https address.")
        case "invalid-url", "Missing URL", "host-not-allowed":
            String(localized: "Check the base URL.")
        case "local-host", "private-address":
            String(localized: "That address can't be used.")
        default:
            ""
        }
    }

    static func apiErrorMessage(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func resolvedBase(format: String, baseURL: String) -> String {
        let displayed = ProviderAPIDefaults.displayBase(format: format, baseURL: baseURL)
        if !displayed.isEmpty { return displayed }
        return format == "google-interactions"
            ? ProviderAPIDefaults.googleBase
            : ProviderAPIDefaults.openAIBase
    }

    private static func chatURL(_ base: String) -> String {
        if base.hasSuffix("/chat/completions") { return base }
        return base + "/chat/completions"
    }

    private static func join(_ base: String, _ path: String) -> String {
        if base.hasSuffix(path) { return base }
        return base + path
    }

    private static func jsonString(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
