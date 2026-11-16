import AiboCore
import AppKit
import SwiftUI

struct HookCleanupEntryRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hook Cleanup")
                        .foregroundStyle(.primary)
                    Text("See which apps left hooks for the agents on this Mac")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
}

struct HookCleanupSettingsView: View {
    var onBack: () -> Void

    @State private var board = HookCleanupBoard.empty
    @State private var selection: [String: Set<String>] = [:]
    @State private var showsSupportedAgents = false
    @State private var writeError: HookCleanupStore.WriteError?

    var body: some View {
        Form {
            Section {
                HookCleanupSummaryRow(
                    appCount: board.apps.count,
                    agentCount: board.localAgents.count,
                    onRescan: reload
                )
            }

            if !board.apps.isEmpty {
                ForEach(board.apps) { app in
                    Section {
                        HookCleanupAppHeader(
                            app: app,
                            isEnabled: !(selection[app.id] ?? []).isEmpty,
                            onRemove: { removeSelected(in: app) }
                        )
                        ForEach(app.injections) { injection in
                            HookCleanupAgentRow(
                                injection: injection,
                                isSelected: (selection[app.id] ?? []).contains(injection.agentName),
                                onToggle: { toggle(injection.agentName, in: app.id) }
                            )
                        }
                        let notInjected = board.localAgents.filter { name in
                            !app.injections.contains { $0.agentName == name }
                        }
                        if !notInjected.isEmpty {
                            HookCleanupNotInjectedRow(names: notInjected)
                        }
                    } header: {
                        if app.id == board.apps.first?.id {
                            Text("Scan Results")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(
            title: String(localized: "Hook Cleanup"),
            canGoBack: true,
            onBack: onBack
        ) {
            ToolbarItem {
                Button {
                    showsSupportedAgents = true
                } label: {
                    Image(systemName: "info.circle.text.page")
                }
                .accessibilityLabel(Text("Checked agents"))
                .popover(isPresented: $showsSupportedAgents, arrowEdge: .bottom) {
                    HookCleanupSupportedAgentsPopover()
                }
            }
        }
        .task { reload() }
        .alert(
            String(localized: "Couldn't Update Hooks"),
            isPresented: Binding(
                get: { writeError != nil },
                set: { if !$0 { writeError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { writeError = nil }
        } message: {
            Text(writeErrorText)
        }
    }

    private var writeErrorText: LocalizedStringResource {
        switch writeError {
        case .invalidFile:
            "This hooks file couldn't be read, so Aibo didn't change it."
        case .failed, nil:
            "The hooks file couldn't be saved. Nothing was changed."
        }
    }

    private func reload() {
        let files = HookCleanupStore.load()
        let next = HookCleanupBoard.make(files: files)
        var selected: [String: Set<String>] = [:]
        for app in next.apps where app.missing {
            selected[app.id] = Set(app.injections.map(\.agentName))
        }
        board = next
        selection = selected
    }

    private func toggle(_ agentName: String, in appID: String) {
        var chosen = selection[appID] ?? []
        if chosen.contains(agentName) {
            chosen.remove(agentName)
        } else {
            chosen.insert(agentName)
        }
        selection[appID] = chosen
    }

    private func removeSelected(in app: HookCleanupBoard.AppCard) {
        let chosen = selection[app.id] ?? []
        let targets = app.injections
            .filter { chosen.contains($0.agentName) }
            .flatMap(\.targets)
        guard !targets.isEmpty else { return }
        do {
            var seen = Set<String>()
            for target in targets {
                let key = target.file.id + "\n" + target.ownerID
                guard seen.insert(key).inserted else { continue }
                try HookCleanupStore.remove(ownerID: target.ownerID, from: target.file)
            }
            reload()
        } catch let error as HookCleanupStore.WriteError {
            writeError = error
            reload()
        } catch {
            writeError = .failed
            reload()
        }
    }
}

private struct HookCleanupSummaryRow: View {
    var appCount: Int
    var agentCount: Int
    var onRescan: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDark ? Color.white : Color.black)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(isDark ? Color.black : Color.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Found \(appCount) injected apps")
                    .font(.body.weight(.semibold))
                Text("Scanned \(agentCount) local agents")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Scan Again", action: onRescan)
        }
    }
}

private struct HookCleanupAppHeader: View {
    var app: HookCleanupBoard.AppCard
    var isEnabled: Bool
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HookCleanupAppIcon(app: app)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.semibold))
                Text(app.missing ? "App is not on this Mac" : "Installed locally")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Text("Remove Hooks")
            }
            .disabled(!isEnabled)
            if !app.missing, let bundlePath = app.bundlePath {
                HookCleanupRevealButton(url: URL(fileURLWithPath: bundlePath))
            }
        }
    }
}

private struct HookCleanupAgentRow: View {
    var injection: HookCleanupBoard.Injection
    var isSelected: Bool
    var onToggle: () -> Void

    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.red : Color.secondary)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(injection.agentName)
                        Text("\(injection.hookCount) hooks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Select \(injection.agentName)"))

            Button {
                showsInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Hook details"))
            .popover(isPresented: $showsInfo, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                HookCleanupInfoPopover(info: HookCleanupInfo(injection: injection))
            }

            if let url = injection.targets.first?.file.url {
                HookCleanupRevealButton(url: url)
            }
        }
    }
}

private struct HookCleanupNotInjectedRow: View {
    var names: [String]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slash.circle")
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("Not injected")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(names.formatted(.list(type: .and, width: .narrow)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct HookCleanupAppIcon: View {
    var app: HookCleanupBoard.AppCard

    var body: some View {
        image
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if app.missing {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay {
                    Image(systemName: "questionmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        } else if let path = app.bundlePath ?? app.resolvedPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var symbol: String {
        switch app.kind {
        case .prompt: "text.quote"
        case .network: "network"
        case .mcpTool: "puzzlepiece.extension"
        case .command, .application, .file, .script: "terminal"
        }
    }
}

private struct HookCleanupRevealButton: View {
    var url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "folder")
                .foregroundStyle(.primary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Show in Finder"))
    }
}

private struct HookCleanupInfo: Identifiable {
    var agentName: String
    var detail: String
    var events: String
    var id: String { agentName + "\n" + detail + "\n" + events }

    init(injection: HookCleanupBoard.Injection) {
        agentName = injection.agentName
        detail = injection.detail
        events = injection.events
    }
}

private struct HookCleanupSupportedAgentsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checked agents")
                .font(.headline)
            ForEach(HookCleanupStore.supportedAgentNames, id: \.self) { name in
                Text(verbatim: name)
            }
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
    }
}

private struct HookCleanupInfoPopover: View {
    var info: HookCleanupInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(info.agentName)
                .font(.headline)
            if !info.events.isEmpty {
                Text(info.events)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !info.detail.isEmpty {
                Text(info.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

private enum HookCleanupBoard {
    struct RemovalTarget {
        var file: HookCleanupStore.File
        var ownerID: String
    }

    struct Injection: Identifiable {
        var agentName: String
        var hookCount: Int
        var detail: String
        var events: String
        var placements: [HookPlacement]
        var targets: [RemovalTarget]
        var id: String { agentName }
    }

    struct AppCard: Identifiable {
        var id: String
        var name: String
        var kind: HookOwnerKind
        var missing: Bool
        var bundlePath: String?
        var resolvedPath: String?
        var injections: [Injection]
    }

    struct Model {
        var apps: [AppCard]
        var localAgents: [String]
    }

    static let empty = Model(apps: [], localAgents: [])

    static func make(files: [HookCleanupStore.File]) -> Model {
        let readable = files.filter { $0.issue == nil }
        var localAgents: [String] = []
        for file in readable where !localAgents.contains(file.agentName) {
            localAgents.append(file.agentName)
        }

        struct Accumulator {
            var name: String
            var kind: HookOwnerKind
            var missing: Bool
            var bundlePath: String?
            var resolvedPath: String?
            var byAgent: [String: Injection]
            var agentOrder: [String]
        }

        var order: [String] = []
        var cards: [String: Accumulator] = [:]
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

        for file in readable {
            for owner in file.inventory.owners {
                let key = cardKey(for: owner)
                let ownerMissing = owner.suggestsRemoval(fileExists: exists)
                var card = cards[key] ?? Accumulator(
                    name: displayName(for: owner),
                    kind: owner.kind,
                    missing: ownerMissing,
                    bundlePath: owner.bundlePath,
                    resolvedPath: owner.resolvedPath,
                    byAgent: [:],
                    agentOrder: []
                )
                card.missing = card.missing && ownerMissing
                if let bundlePath = preferredBundle(card.bundlePath, owner.bundlePath) {
                    card.bundlePath = bundlePath
                    card.name = displayName(for: owner, bundlePath: bundlePath)
                }
                var injection = card.byAgent[file.agentName] ?? Injection(
                    agentName: file.agentName,
                    hookCount: 0,
                    detail: owner.detail,
                    events: "",
                    placements: [],
                    targets: []
                )
                injection.hookCount += owner.placements.count
                if injection.detail.isEmpty { injection.detail = owner.detail }
                injection.placements.append(contentsOf: owner.placements)
                injection.targets.append(RemovalTarget(file: file, ownerID: owner.id))
                if !card.agentOrder.contains(file.agentName) {
                    card.agentOrder.append(file.agentName)
                }
                card.byAgent[file.agentName] = injection
                if cards[key] == nil { order.append(key) }
                cards[key] = card
            }
        }

        let apps = order.compactMap { id -> AppCard? in
            guard let card = cards[id] else { return nil }
            let injections = card.agentOrder.compactMap { name -> Injection? in
                guard var injection = card.byAgent[name] else { return nil }
                injection.events = eventSummary(injection.placements)
                return injection
            }
            return AppCard(
                id: id,
                name: card.name,
                kind: card.kind,
                missing: card.missing,
                bundlePath: card.bundlePath,
                resolvedPath: card.resolvedPath,
                injections: injections
            )
        }
        .sorted { lhs, rhs in
            if lhs.missing != rhs.missing { return lhs.missing && !rhs.missing }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.id < rhs.id }
            return order == .orderedAscending
        }

        return Model(apps: apps, localAgents: localAgents)
    }

    /// One product is one card. `/Applications/aibo.app` and an Xcode build of
    /// the same bundle are the same Aibo, so Cursor and Codex stay on one card.
    private static func cardKey(for owner: HookOwner) -> String {
        guard owner.kind == .application, let bundlePath = owner.bundlePath else {
            return owner.id
        }
        if let identifier = Bundle(url: URL(fileURLWithPath: bundlePath))?.bundleIdentifier,
           !identifier.isEmpty {
            return "bundle:\(identifier)"
        }
        return "app:\(owner.title.lowercased())"
    }

    /// Prefer the copy a person installed over a build folder, when both exist.
    private static func preferredBundle(_ current: String?, _ candidate: String?) -> String? {
        switch (current, candidate) {
        case (nil, let candidate):
            return candidate
        case (let current?, nil):
            return current
        case (let current?, let candidate?):
            let currentExists = FileManager.default.fileExists(atPath: current)
            let candidateExists = FileManager.default.fileExists(atPath: candidate)
            if candidateExists, !currentExists { return candidate }
            if currentExists, !candidateExists { return current }
            let currentBuild = current.contains("/DerivedData/") || current.contains("/Build/")
            let candidateBuild = candidate.contains("/DerivedData/") || candidate.contains("/Build/")
            if currentBuild, !candidateBuild { return candidate }
            return current
        }
    }

    private static func displayName(for owner: HookOwner, bundlePath: String? = nil) -> String {
        let path = bundlePath ?? owner.bundlePath
        if owner.kind == .application,
           let path,
           FileManager.default.fileExists(atPath: path),
           let bundle = Bundle(url: URL(fileURLWithPath: path)) {
            let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            if let display, !display.isEmpty { return display }
            if let bundleName, !bundleName.isEmpty { return bundleName }
        }
        if owner.title.isEmpty { return String(localized: "Prompt rule") }
        return owner.title
    }

    private static func eventSummary(_ placements: [HookPlacement]) -> String {
        var labels: [String] = []
        var seen = Set<String>()
        for placement in placements {
            let title = hookEventTitle(placement.eventName)
            let label = if let matcher = placement.matcher, !matcher.isEmpty {
                "\(title) (\(matcher))"
            } else {
                title
            }
            if seen.insert(label).inserted { labels.append(label) }
        }
        return labels.formatted(.list(type: .and, width: .narrow))
    }

    private static func hookEventTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "sessionstart": String(localized: "Session starts")
        case "sessionend": String(localized: "Session ends")
        case "beforesubmitprompt", "userpromptsubmit": String(localized: "Before a prompt is sent")
        case "pretooluse": String(localized: "Before a tool runs")
        case "posttooluse": String(localized: "After a tool runs")
        case "posttoolusefailure": String(localized: "After a tool fails")
        case "beforeshellexecution": String(localized: "Before a shell command")
        case "aftershellexecution": String(localized: "After a shell command")
        case "beforemcpexecution": String(localized: "Before an MCP call")
        case "aftermcpexecution": String(localized: "After an MCP call")
        case "beforereadfile": String(localized: "Before a file is read")
        case "afterfileedit": String(localized: "After a file is edited")
        case "afteragentresponse": String(localized: "After a reply")
        case "afteragentthought": String(localized: "After a thought")
        case "subagentstart": String(localized: "When a subagent starts")
        case "subagentstop": String(localized: "When a subagent stops")
        case "stop": String(localized: "When the agent stops")
        case "permissionrequest": String(localized: "On a permission request")
        case "precompact", "precompress": String(localized: "Before context is compacted")
        case "notification": String(localized: "On a notification")
        case "setup": String(localized: "When setup runs")
        case "beforetool": String(localized: "Before a tool runs")
        case "aftertool": String(localized: "After a tool runs")
        case "beforeagent": String(localized: "Before the agent runs")
        case "afteragent": String(localized: "After the agent runs")
        case "beforemodel": String(localized: "Before the model runs")
        case "aftermodel": String(localized: "After the model runs")
        case "beforetoolselection": String(localized: "Before a tool is chosen")
        case "userpromptsubmitted", "pre_user_prompt": String(localized: "Before a prompt is sent")
        case "agentstop", "post_cascade_response": String(localized: "When the agent stops")
        case "erroroccurred": String(localized: "When an error occurs")
        case "pre_read_code": String(localized: "Before a file is read")
        case "post_read_code": String(localized: "After a file is read")
        case "pre_write_code": String(localized: "Before code is written")
        case "post_write_code": String(localized: "After code is written")
        case "pre_run_command": String(localized: "Before a shell command")
        case "post_run_command": String(localized: "After a shell command")
        case "pre_mcp_tool_use": String(localized: "Before an MCP call")
        case "post_mcp_tool_use": String(localized: "After an MCP call")
        case "beforetabfileread": String(localized: "Before Tab reads a file")
        case "aftertabfileedit": String(localized: "After Tab edits a file")
        default: name
        }
    }
}
