import AiboCore
import AiboIngest
import AppKit
import Foundation
import Observation
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
        case running
        case result(summary: String, copyText: String?)
        case failed(String)
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
                let raw = values[control.key] ?? ""
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

    var layoutHeights: [CGFloat] {
        switch phase {
        case .editing:
            [ExtensionBubbleMetrics.promptHeight(kinds: groupKinds)]
        case .running:
            [ExtensionBubbleMetrics.statusHeight(text: String(localized: "Working…"))]
        case .result(let summary, _):
            [ExtensionBubbleMetrics.statusHeight(text: summary)]
        case .failed(let message):
            [ExtensionBubbleMetrics.statusHeight(text: message)]
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
    private(set) var lastError: String?
    private var store = ExtensionStore.live()
    private var runGeneration = 0

    var layoutHeights: [CGFloat]? {
        guard let session, !session.layoutHeights.isEmpty else { return nil }
        return session.layoutHeights
    }

    var layoutToken: String {
        guard let session else { return "" }
        switch session.phase {
        case .editing:
            return "\(session.pluginID)-editing"
        case .running:
            return "\(session.pluginID)-running"
        case .result(let summary, _):
            return "\(session.pluginID)-result-\(summary.count)"
        case .failed(let message):
            return "\(session.pluginID)-failed-\(message.count)"
        }
    }

    var needsKeyWindow: Bool {
        if case .editing = session?.phase { return true }
        return false
    }

    var manualPlugins: [ExtensionRecord] {
        plugins.filter { $0.enabled && $0.manifest.hasManualTrigger }
    }

    private init() {}

    func start() {
        reload()
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

    func install(from directory: URL) {
        do {
            _ = try store.install(from: directory)
            lastError = nil
            reload()
        } catch {
            lastError = String(localized: "Couldn't install the plugin.")
        }
    }

    func installIncludedPrototypes() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Extensions", isDirectory: true) else {
            lastError = String(localized: "Couldn't install the plugin.")
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var failed = false
        for name in names where !name.hasPrefix(".") {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            do {
                _ = try store.install(from: directory)
            } catch {
                failed = true
            }
        }
        lastError = failed ? String(localized: "Couldn't install the plugin.") : nil
        reload()
    }

    func uninstall(id: String) {
        if session?.pluginID == id {
            cancelSession()
        }
        let record = plugins.first { $0.id == id }
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

    func beginManualPrompt(id: String) {
        guard let record = plugins.first(where: { $0.id == id }),
              record.enabled,
              record.manifest.hasManualTrigger
        else { return }
        if case .running = session?.phase, session?.pluginID == id {
            return
        }
        let form = promptForm(for: record)
        session = ExtensionPromptSession(
            pluginID: record.id,
            pluginName: record.copy.name,
            groups: form.groups,
            values: form.values,
            toggles: form.toggles,
            required: form.required
        )
        publishLayout()
    }

    func confirmPrompt() {
        guard let session, case .editing = session.phase else { return }
        guard let input = session.submissionInput() else { return }
        session.phase = .running
        runGeneration += 1
        let generation = runGeneration
        let pluginID = session.pluginID
        publishLayout()
        Task {
            let outcome = await run(id: pluginID, trigger: "manual", input: input, depth: 0)
            guard generation == runGeneration, self.session?.pluginID == pluginID else { return }
            switch outcome {
            case .bubbles(let bubbles):
                let bubble = bubbles.first
                let summary = bubble?.summary ?? String(localized: "Plugin failed")
                let copyText = bubble?.actions.first { $0.copyText != nil }?.copyText ?? summary
                self.session?.phase = .result(summary: summary, copyText: copyText)
            case .failed(let message):
                self.session?.phase = .failed(message)
            }
            publishLayout()
        }
    }

    func copyResult() {
        guard case .result(_, let copyText) = session?.phase, let copyText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: .string)
    }

    func cancelSession() {
        runGeneration += 1
        session = nil
        publishLayout()
        AiboPanelController.shared.clearExtensionCardFrame()
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
                for (key, request) in requests {
                    next[key] = await fulfill(request, caller: record, depth: depth)
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
        depth: Int
    ) async -> ExtensionValue {
        switch request.method {
        case "aibo/llm":
            guard depth == 0 else {
                return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
            }
            guard let provider = plugins.first(where: { $0.enabled && $0.manifest.providesModel }) else {
                return .object(["error": .object(["message": .string(String(localized: "The AI provider plugin is off."))])])
            }
            return await providerOutput(id: provider.id, params: request.params)
        case "aibo/fetch":
            let hosts = allowedHosts(for: caller)
            let response = await ExtensionFetch.perform(params: request.params, allowedHosts: hosts)
            return .object(response)
        default:
            return .object(["error": .object(["message": .string("Unsupported request")])])
        }
    }

    private func providerOutput(id: String, params: [String: ExtensionValue]) async -> ExtensionValue {
        guard let record = plugins.first(where: { $0.id == id }) else {
            return .object(["error": .object(["message": .string(String(localized: "The AI provider plugin is off."))])])
        }
        guard let source = try? String(contentsOf: record.directory.appendingPathComponent(record.manifest.entry), encoding: .utf8) else {
            return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
        }
        incrementInvocations(id: id)
        let settings = runtimeSettings(for: record)
        let generation = runGeneration
        var responses: [String: ExtensionValue] = [:]
        var requestState = ""
        for _ in 0..<4 {
            if generation != runGeneration {
                return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
            }
            let parameters = runParameters(
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
                        next[key] = await fulfill(request, caller: record, depth: 1)
                    }
                }
                responses = next
            }
        }
        return .object(["error": .object(["message": .string(String(localized: "Plugin failed"))])])
    }

    private func runParameters(
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
        return parameters
    }

    private func allowedHosts(for record: ExtensionRecord) -> Set<String> {
        var hosts = Set(record.manifest.network.hosts.map { $0.lowercased() })
        let settings = runtimeSettings(for: record)
        if let base = settings["baseURL"]?.stringValue, let host = ExtensionURLPolicy.host(ofURLString: base) {
            hosts.insert(host)
        }
        if record.manifest.providesModel {
            hosts.insert("generativelanguage.googleapis.com")
            hosts.insert("api.openai.com")
        }
        return hosts
    }

    private func runtimeSettings(for record: ExtensionRecord) -> [String: ExtensionValue] {
        var values = store.loadSettings(id: record.id)
        guard let schema = record.manifest.settings else { return values }
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
        return values
    }

    private func secretValues(for record: ExtensionRecord) -> [String] {
        guard let schema = record.manifest.settings else { return [] }
        return schema.properties.compactMap { key, field in
            guard field.sensitive else { return nil }
            return KeychainStore.string(forAccount: keychainAccount(id: record.id, key: key))
        }.filter { !$0.isEmpty }
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
