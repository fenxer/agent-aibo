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

    @State private var files: [HookCleanupStore.File] = []
    @State private var pending: PendingHookRemoval?
    @State private var writeError: HookCleanupStore.WriteError?

    var body: some View {
        Form {
            if presentFiles.isEmpty {
                Section {
                    Text("No hook files on this Mac yet")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("You can remove a hook here only when its app or file is no longer on this Mac.")
                }
            } else {
                ForEach(presentFiles) { file in
                    HookCleanupFileSection(
                        file: file,
                        explainsRemoval: file.id == presentFiles.first?.id,
                        onRemove: { ownerID, name in
                            pending = PendingHookRemoval(file: file, ownerID: ownerID, name: name)
                        }
                    )
                }
            }
            if !missingAgentNames.isEmpty {
                Section {
                    Text("No hook file yet for \(missingAgentNames.formatted(.list(type: .and, width: .narrow))).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(
            title: String(localized: "Hook Cleanup"),
            canGoBack: true,
            onBack: onBack
        )
        .task {
            files = HookCleanupStore.load()
        }
        .confirmationDialog(
            pendingTitle,
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: performRemoval)
            Button("Cancel", role: .cancel) {
                pending = nil
            }
        } message: {
            Text("Its hooks will be taken out of the file. Hooks from other apps stay.")
        }
        .alert(
            String(localized: "Couldn't Update Hooks"),
            isPresented: Binding(
                get: { writeError != nil },
                set: { if !$0 { writeError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                writeError = nil
            }
        } message: {
            Text(writeErrorText)
        }
    }

    private var pendingTitle: String {
        guard let pending else { return "" }
        return String(localized: "Remove “\(pending.name)” from \(pending.file.heading)?")
    }

    private var writeErrorText: LocalizedStringResource {
        switch writeError {
        case .invalidFile:
            "This hooks file couldn't be read, so Aibo didn't change it."
        case .failed, nil:
            "The hooks file couldn't be saved. Nothing was changed."
        }
    }

    private var presentFiles: [HookCleanupStore.File] {
        files.filter { $0.issue != .missing }
    }

    private var missingAgentNames: [String] {
        var seen = Set<String>()
        return files.compactMap { file in
            guard file.issue == .missing, seen.insert(file.agentName).inserted else { return nil }
            return file.agentName
        }
    }

    private func performRemoval() {
        guard let pending else { return }
        self.pending = nil
        do {
            try HookCleanupStore.remove(ownerID: pending.ownerID, from: pending.file)
            files = HookCleanupStore.load()
        } catch let error as HookCleanupStore.WriteError {
            writeError = error
        } catch {
            writeError = .failed
        }
    }
}

private struct PendingHookRemoval: Identifiable {
    var file: HookCleanupStore.File
    var ownerID: String
    var name: String
    var id: String { file.id + "\n" + ownerID }
}

private struct HookCleanupFileSection: View {
    var file: HookCleanupStore.File
    var explainsRemoval: Bool
    var onRemove: (String, String) -> Void

    var body: some View {
        Section {
            HookCleanupFileContent(file: file, onRemove: onRemove)
        } header: {
            Text(verbatim: file.heading)
        } footer: {
            HookCleanupFileFooter(
                unrecognizedCount: file.issue == nil ? file.inventory.unrecognizedCount : 0,
                explainsRemoval: explainsRemoval
            )
        }
    }
}

private struct HookCleanupFileFooter: View {
    var unrecognizedCount: Int
    var explainsRemoval: Bool

    var body: some View {
        if explainsRemoval || unrecognizedCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if explainsRemoval {
                    Text("You can remove a hook here only when its app or file is no longer on this Mac.")
                }
                if unrecognizedCount == 1 {
                    Text("One entry was left as it is because Aibo couldn't tell what it runs.")
                } else if unrecognizedCount > 1 {
                    Text("\(unrecognizedCount) entries were left as they are because Aibo couldn't tell what they run.")
                }
            }
        }
    }
}

private struct HookCleanupFileContent: View {
    var file: HookCleanupStore.File
    var onRemove: (String, String) -> Void

    var body: some View {
        if file.issue == .missing {
            Text("No hooks file")
                .foregroundStyle(.secondary)
        } else if file.issue == .unreadable {
            Text("This hooks file couldn't be read, so Aibo didn't change it.")
                .foregroundStyle(.red)
        } else if rows.isEmpty {
            Text("No hooks")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows) { row in
                HookCleanupOwnerRow(row: row) {
                    onRemove(row.ownerID, row.name)
                }
            }
        }
    }

    private var rows: [HookCleanupListing.Row] {
        HookCleanupListing.rows(in: file)
    }
}

private struct HookCleanupOwnerRow: View {
    var row: HookCleanupListing.Row
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HookCleanupOwnerIcon(row: row)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(row.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !row.eventSummary.isEmpty {
                    Text(row.eventSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !row.detail.isEmpty, row.detail != row.name {
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if row.missing {
                Button(role: .destructive, action: onRemove) {
                    Text("Remove")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove \(row.name)"))
            }
        }
    }
}

private struct HookCleanupOwnerIcon: View {
    var row: HookCleanupListing.Row

    var body: some View {
        image
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if let path = iconPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: symbolName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var symbolName: String {
        switch row.kind {
        case .prompt:
            "text.quote"
        case .network:
            "network"
        case .mcpTool:
            "puzzlepiece.extension"
        case .command, .application, .file, .script:
            "terminal"
        }
    }

    private var iconPath: String? {
        switch row.kind {
        case .application:
            row.bundlePath
        case .file, .script:
            row.resolvedPath
        case .command, .prompt, .network, .mcpTool:
            nil
        }
    }
}

private enum HookCleanupListing {
    struct Row: Identifiable {
        var ownerID: String
        var kind: HookOwnerKind
        var name: String
        var status: String
        var missing: Bool
        var detail: String
        var bundlePath: String?
        var resolvedPath: String?
        var eventSummary: String
        var id: String { ownerID }
    }

    static func rows(in file: HookCleanupStore.File) -> [Row] {
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        let rows = file.inventory.owners.map { owner -> Row in
            let missing = owner.suggestsRemoval(fileExists: exists)
            let name = displayName(for: owner)
            return Row(
                ownerID: owner.id,
                kind: owner.kind,
                name: name,
                status: status(kind: owner.kind, missing: missing),
                missing: missing,
                detail: owner.detail,
                bundlePath: owner.bundlePath,
                resolvedPath: owner.resolvedPath,
                eventSummary: eventSummary(owner.placements)
            )
        }
        return rows.sorted { lhs, rhs in
            if lhs.missing != rhs.missing { return lhs.missing && !rhs.missing }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.ownerID < rhs.ownerID }
            return order == .orderedAscending
        }
    }

    private static func displayName(for owner: HookOwner) -> String {
        if owner.kind == .application,
           let bundlePath = owner.bundlePath,
           FileManager.default.fileExists(atPath: bundlePath),
           let bundle = Bundle(url: URL(fileURLWithPath: bundlePath)) {
            let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            if let display, !display.isEmpty { return display }
            if let bundleName, !bundleName.isEmpty { return bundleName }
        }
        if owner.title.isEmpty {
            return String(localized: "Prompt rule")
        }
        return owner.title
    }

    private static func status(kind: HookOwnerKind, missing: Bool) -> String {
        switch kind {
        case .application:
            missing ? String(localized: "App not found") : String(localized: "On this Mac")
        case .file, .script:
            missing ? String(localized: "File not found") : String(localized: "File is still here")
        case .command:
            String(localized: "Not tied to an app")
        case .prompt:
            String(localized: "Prompt rule")
        case .network:
            String(localized: "Network request")
        case .mcpTool:
            String(localized: "MCP tool")
        }
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
            if seen.insert(label).inserted {
                labels.append(label)
            }
        }
        return labels.formatted(.list(type: .and, width: .narrow))
    }

    private static func hookEventTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "sessionstart":
            String(localized: "Session starts")
        case "sessionend":
            String(localized: "Session ends")
        case "beforesubmitprompt", "userpromptsubmit":
            String(localized: "Before a prompt is sent")
        case "pretooluse":
            String(localized: "Before a tool runs")
        case "posttooluse":
            String(localized: "After a tool runs")
        case "posttoolusefailure":
            String(localized: "After a tool fails")
        case "beforeshellexecution":
            String(localized: "Before a shell command")
        case "aftershellexecution":
            String(localized: "After a shell command")
        case "beforemcpexecution":
            String(localized: "Before an MCP call")
        case "aftermcpexecution":
            String(localized: "After an MCP call")
        case "beforereadfile":
            String(localized: "Before a file is read")
        case "afterfileedit":
            String(localized: "After a file is edited")
        case "afteragentresponse":
            String(localized: "After a reply")
        case "afteragentthought":
            String(localized: "After a thought")
        case "subagentstart":
            String(localized: "When a subagent starts")
        case "subagentstop":
            String(localized: "When a subagent stops")
        case "stop":
            String(localized: "When the agent stops")
        case "permissionrequest":
            String(localized: "On a permission request")
        case "precompact", "precompress":
            String(localized: "Before context is compacted")
        case "notification":
            String(localized: "On a notification")
        case "setup":
            String(localized: "When setup runs")
        case "beforetool":
            String(localized: "Before a tool runs")
        case "aftertool":
            String(localized: "After a tool runs")
        case "beforeagent":
            String(localized: "Before the agent runs")
        case "afteragent":
            String(localized: "After the agent runs")
        case "beforemodel":
            String(localized: "Before the model runs")
        case "aftermodel":
            String(localized: "After the model runs")
        case "beforetoolselection":
            String(localized: "Before a tool is chosen")
        case "userpromptsubmitted", "pre_user_prompt":
            String(localized: "Before a prompt is sent")
        case "agentstop", "post_cascade_response":
            String(localized: "When the agent stops")
        case "erroroccurred":
            String(localized: "When an error occurs")
        case "pre_read_code":
            String(localized: "Before a file is read")
        case "post_read_code":
            String(localized: "After a file is read")
        case "pre_write_code":
            String(localized: "Before code is written")
        case "post_write_code":
            String(localized: "After code is written")
        case "pre_run_command":
            String(localized: "Before a shell command")
        case "post_run_command":
            String(localized: "After a shell command")
        case "pre_mcp_tool_use":
            String(localized: "Before an MCP call")
        case "post_mcp_tool_use":
            String(localized: "After an MCP call")
        case "beforetabfileread":
            String(localized: "Before Tab reads a file")
        case "aftertabfileedit":
            String(localized: "After Tab edits a file")
        default:
            name
        }
    }
}
