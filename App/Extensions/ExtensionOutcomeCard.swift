import AiboCore
import AppKit
import SwiftUI

enum ExtensionOutcomeKind: Equatable {
    case running
    case completed
    case warning
    case failed

    var title: LocalizedStringResource {
        switch self {
        case .running:
            LocalizedStringResource(
                "extension-outcome-running",
                defaultValue: "Running",
                comment: "Badge on a plugin bubble while the plugin is working."
            )
        case .completed:
            LocalizedStringResource(
                "extension-outcome-completed",
                defaultValue: "Completed",
                comment: "Badge on a plugin bubble after a normal result."
            )
        case .warning:
            LocalizedStringResource(
                "extension-outcome-warning",
                defaultValue: "Warning",
                comment: "Badge on a plugin bubble for a warning, including a missing dependency."
            )
        case .failed:
            LocalizedStringResource(
                "extension-outcome-failed",
                defaultValue: "Failed",
                comment: "Badge on a plugin bubble when the result was not the expected output."
            )
        }
    }

    var symbol: String? {
        switch self {
        case .running: nil
        case .completed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    /// Solid system green, yellow, and red. Running stays a translucent gray.
    var fill: Color {
        switch self {
        case .running: Color.gray.opacity(0.28)
        case .completed: .green
        case .warning: .yellow
        case .failed: .red
        }
    }

    /// Same hues as `fill`, opaque so `Glass.tint` can dye the capsule. Running stays clear.
    var glassTint: Color? {
        switch self {
        case .running: nil
        case .completed: .green
        case .warning: .yellow
        case .failed: .red
        }
    }

    var content: Color {
        switch self {
        case .running: .primary
        case .completed, .failed: .white
        case .warning: .black
        }
    }
}

struct ExtensionDependencyRowModel: Identifiable, Equatable {
    var issue: ExtensionDependencyIssue
    var icon: ExtensionIcon
    var directory: URL?
    var enabled: Bool

    var id: String { issue.id }
}

struct ExtensionRunningCard: View {
    var name: String
    var directory: URL?
    var icon: ExtensionIcon
    var message: String

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        if chrome == .window {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeHeader(name: name, directory: directory, icon: icon, kind: .running)
            messageWell
                .padding(.top, chrome == .window ? -ExtensionBubbleMetrics.windowHeaderContentTrim : 0)
        }
    }

    @ViewBuilder
    private var messageWell: some View {
        if chrome == .window {
            ScrollView {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(ExtensionBubbleMetrics.runningWellPadding)
            .background { well }
        } else {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExtensionBubbleMetrics.runningWellPadding)
                .background { well }
        }
    }

    @ViewBuilder
    private var well: some View {
        if chrome == .window {
            ExtensionWindowContentFill(
                topRadius: ExtensionBubbleMetrics.inputCornerRadius,
                color: Color(nsColor: .secondarySystemFill)
            )
        } else {
            RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                .fill(Color(nsColor: .secondarySystemFill))
        }
    }
}

struct ExtensionOutcomeCard: View {
    var name: String
    var directory: URL?
    var icon: ExtensionIcon
    var kind: ExtensionOutcomeKind
    var text: String
    var copiesIssue: Bool
    var onCopy: () -> Void
    var onClose: () -> Void

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        if chrome == .window {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeHeader(name: name, directory: directory, icon: icon, kind: kind)
            if chrome == .window {
                windowContent
            } else {
                ExtensionOutcomeBody(text: text)
                ExtensionOutcomeActions(copiesIssue: copiesIssue, onCopy: onCopy, onClose: onClose)
            }
        }
    }

    /// The result fills the space above the buttons. The platter stops there.
    private var windowContent: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeBody(text: text)
                .padding(ExtensionBubbleMetrics.formPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    ExtensionWindowContentFill(
                        topRadius: ExtensionBubbleMetrics.groupCornerRadius,
                        color: Color(nsColor: .secondarySystemFill)
                    )
                }
                .clipShape(
                    ConcentricRectangle(
                        uniformTopCorners: .fixed(ExtensionBubbleMetrics.groupCornerRadius),
                        uniformBottomCorners: .concentric(
                            minimum: .fixed(ExtensionBubbleMetrics.groupCornerRadius)
                        )
                    )
                )
            ExtensionOutcomeActions(copiesIssue: copiesIssue, onCopy: onCopy, onClose: onClose)
        }
    }
}

struct ExtensionDependencyCard: View {
    var name: String
    var directory: URL?
    var icon: ExtensionIcon
    var rows: [ExtensionDependencyRowModel]
    var installingID: String?
    var onInstall: (String) -> Void
    var onEnabled: (Bool, String) -> Void
    var onCopy: () -> Void
    var onClose: () -> Void

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        if chrome == .window {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeHeader(name: name, directory: directory, icon: icon, kind: .warning)
            Text("Missing Dependency")
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: ExtensionBubbleMetrics.dependencyTitleHeight, alignment: .leading)
                .padding(.top, chrome == .window ? -ExtensionBubbleMetrics.windowHeaderContentTrim : 0)
            rowList
            ExtensionOutcomeActions(copiesIssue: true, onCopy: onCopy, onClose: onClose)
        }
    }

    private var rowStack: some View {
        VStack(spacing: ExtensionBubbleMetrics.dependencyRowSpacing) {
            ForEach(rows) { row in
                ExtensionDependencyRow(
                    row: row,
                    isInstalling: installingID == row.issue.subjectID,
                    onInstall: { onInstall(row.issue.subjectID) },
                    onEnabled: { onEnabled($0, row.issue.subjectID) }
                )
            }
        }
    }

    @ViewBuilder
    private var rowList: some View {
        if chrome == .window {
            ScrollView { rowStack }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            rowStack
        }
    }
}

private struct ExtensionOutcomeHeader: View {
    var name: String
    var directory: URL?
    var icon: ExtensionIcon
    var kind: ExtensionOutcomeKind
    var onClose: (() -> Void)?

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        HStack(spacing: chrome == .window ? ExtensionBubbleMetrics.windowGlassButtonSpacing : 6) {
            pluginMark
            Spacer(minLength: 8)
            if chrome == .window {
                ExtensionOutcomeBadge(kind: kind, showsFill: false)
                    .modifier(ExtensionWindowGlassButton(tint: kind.glassTint))
                ExtensionBubbleCornerButton()
                    .modifier(ExtensionWindowGlassButton())
            } else {
                ExtensionOutcomeBadge(kind: kind)
                closeButton
                ExtensionBubbleCornerButton()
            }
        }
        .modifier(ExtensionWindowTitleBand(enabled: chrome == .window))
    }

    private var pluginMark: some View {
        HStack(spacing: 6) {
            ExtensionIconBadge(
                icon: icon,
                directory: directory,
                side: ExtensionBubbleMetrics.pluginIconSize,
                cornerRadius: ExtensionBubbleMetrics.pluginIconCornerRadius,
                symbolPointSize: 14
            )
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            ExtensionBubbleCloseButton(action: onClose)
        }
    }
}

private struct ExtensionOutcomeBadge: View {
    var kind: ExtensionOutcomeKind
    /// Window chrome tints the glass instead of painting this fill.
    var showsFill: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            mark
            Text(kind.title)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundStyle(kind.content)
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(height: ExtensionBubbleMetrics.pluginHeaderHeight)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            if showsFill {
                Capsule().fill(kind.fill)
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        if kind == .running {
            ProgressView()
                .controlSize(.small)
                .tint(kind.content)
        } else if let symbol = kind.symbol {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .symbolRenderingMode(.monochrome)
        }
    }
}

private struct ExtensionOutcomeBody: View {
    var text: String

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        if chrome == .window {
            textScroll
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(minHeight: 36)
        } else {
            textScroll
                .frame(height: ExtensionBubbleMetrics.textBlockHeight(text))
        }
    }

    private var textScroll: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(chrome == .window ? .hidden : .automatic)
    }
}

/// Copy / Close on a finished card. The panel is not allowed to become key, so
/// SwiftUI's button asks `_NSGlassEffectWindow` to become key, that window
/// returns NO, and AppKit drops the click. A hook bubble under the card also
/// wins the gesture. The panel runs the action from this frame instead.
final class ExtensionOutcomeActionToken {
    var frame: CGRect = .null
    var perform: @MainActor () -> Void = {}
}

enum ExtensionOutcomeActionTracker {
    private static var tokens: [ExtensionOutcomeActionToken] = []

    static func register(_ token: ExtensionOutcomeActionToken) {
        guard tokens.contains(where: { $0 === token }) == false else { return }
        tokens.append(token)
    }

    static func unregister(_ token: ExtensionOutcomeActionToken) {
        tokens.removeAll { $0 === token }
    }

    @MainActor
    static func perform(at point: NSPoint) -> Bool {
        for token in tokens.reversed() where token.frame.contains(point) {
            token.perform()
            return true
        }
        return false
    }
}

private struct ExtensionOutcomeActions: View {
    var copiesIssue: Bool
    var onCopy: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if copiesIssue {
                ExtensionOutcomeActionButton(title: "Copy Issue", prominent: true, action: onCopy)
            } else {
                ExtensionOutcomeActionButton(title: "Copy", prominent: true, action: onCopy)
            }
            ExtensionOutcomeActionButton(title: "Close", prominent: false, action: onClose)
        }
        .controlSize(.extraLarge)
        .frame(height: ExtensionBubbleMetrics.buttonRowHeight, alignment: .leading)
    }
}

/// Anchored result buttons. The detached window can become key, so it keeps the
/// system button and does not register a frame.
private struct ExtensionOutcomeActionButton: View {
    var title: LocalizedStringKey
    var prominent: Bool
    var action: () -> Void

    @Environment(\.extensionBubbleChrome) private var chrome
    @State private var token = ExtensionOutcomeActionToken()

    var body: some View {
        button
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(AiboPanelSpace.name))
            } action: { frame in
                guard chrome == .anchored else {
                    token.frame = .null
                    ExtensionOutcomeActionTracker.unregister(token)
                    return
                }
                guard frame.width > 8, frame.height > 8, frame.width < 280, frame.height < 64 else {
                    token.frame = .null
                    return
                }
                token.frame = frame.insetBy(dx: -2, dy: -2)
                token.perform = action
                ExtensionOutcomeActionTracker.register(token)
            }
            .onDisappear {
                ExtensionOutcomeActionTracker.unregister(token)
            }
    }

    @ViewBuilder
    private var button: some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
        }
    }
}

private struct ExtensionDependencyRow: View {
    var row: ExtensionDependencyRowModel
    var isInstalling: Bool
    var onInstall: () -> Void
    var onEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ExtensionIconBadge(
                icon: row.icon,
                directory: row.directory,
                side: 28,
                cornerRadius: 6,
                symbolPointSize: 14
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.issue.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !row.issue.summary.isEmpty {
                    Text(row.issue.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            remedy
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: ExtensionBubbleMetrics.dependencyRowHeight, maxHeight: ExtensionBubbleMetrics.dependencyRowHeight)
        .background {
            RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.groupCornerRadius, style: .continuous)
                .fill(Color(nsColor: .tertiarySystemFill))
        }
    }

    @ViewBuilder
    private var remedy: some View {
        switch row.issue.remedy {
        case .install:
            Button(action: onInstall) {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Install")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isInstalling)
        case .enable:
            ExtensionEnableSwitch(isOn: row.enabled, onChange: onEnabled)
        case .unavailable:
            EmptyView()
        }
    }
}

/// Switch frame in the pet panel, top-left, same space as prompt fields.
///
/// A click on this control asks the bubble's `_NSGlassEffectWindow` to become
/// key. That window refuses, and AppKit drops the click, so the switch never
/// toggles. The panel's mouse monitor turns the dependency on and swallows
/// the event before it reaches the glass window.
final class ExtensionEnableSwitchToken {
    var frame: CGRect = .null
    var turnOn: @MainActor () -> Void = {}
}

enum ExtensionEnableSwitchTracker {
    private static var tokens: [ExtensionEnableSwitchToken] = []

    static func register(_ token: ExtensionEnableSwitchToken) {
        guard tokens.contains(where: { $0 === token }) == false else { return }
        tokens.append(token)
    }

    static func unregister(_ token: ExtensionEnableSwitchToken) {
        tokens.removeAll { $0 === token }
    }

    @MainActor
    static func turnOn(at point: NSPoint) -> Bool {
        for token in tokens.reversed() where token.frame.contains(point) {
            token.turnOn()
            return true
        }
        return false
    }
}

/// Small system switch. The pet panel enables the dependency itself.
private struct ExtensionEnableSwitch: View {
    var isOn: Bool
    var onChange: (Bool) -> Void
    @State private var token = ExtensionEnableSwitchToken()
    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        Toggle(
            "Turn On",
            isOn: Binding(
                get: { isOn },
                set: { onChange($0) }
            )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(AiboPanelSpace.name))
        } action: { frame in
            guard chrome == .anchored else {
                token.frame = .null
                ExtensionEnableSwitchTracker.unregister(token)
                return
            }
            guard frame.width > 8, frame.height > 8, frame.width < 80, frame.height < 48 else {
                token.frame = .null
                return
            }
            token.frame = frame.insetBy(dx: -4, dy: -4)
            token.turnOn = { onChange(true) }
            ExtensionEnableSwitchTracker.register(token)
        }
        .onDisappear {
            ExtensionEnableSwitchTracker.unregister(token)
        }
    }
}
