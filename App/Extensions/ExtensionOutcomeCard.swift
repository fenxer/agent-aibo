import AiboCore
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
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeHeader(name: name, directory: directory, icon: icon, kind: .running, onClose: onClose)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExtensionBubbleMetrics.runningWellPadding)
                .background {
                    RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .secondarySystemFill))
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeHeader(name: name, directory: directory, icon: icon, kind: kind)
            ExtensionOutcomeBody(text: text)
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

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            ExtensionOutcomeHeader(name: name, directory: directory, icon: icon, kind: .warning)
            Text("Missing Dependency")
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: ExtensionBubbleMetrics.dependencyTitleHeight, alignment: .leading)
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
            ExtensionOutcomeActions(copiesIssue: true, onCopy: onCopy, onClose: onClose)
        }
    }
}

private struct ExtensionOutcomeHeader: View {
    var name: String
    var directory: URL?
    var icon: ExtensionIcon
    var kind: ExtensionOutcomeKind
    var onClose: (() -> Void)?

    var body: some View {
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
            Spacer(minLength: 8)
            ExtensionOutcomeBadge(kind: kind)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .frame(height: ExtensionBubbleMetrics.pluginHeaderHeight, alignment: .leading)
    }
}

private struct ExtensionOutcomeBadge: View {
    var kind: ExtensionOutcomeKind

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
        .background(kind.fill, in: Capsule())
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

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: ExtensionBubbleMetrics.textBlockHeight(text))
    }
}

private struct ExtensionOutcomeActions: View {
    var copiesIssue: Bool
    var onCopy: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if copiesIssue {
                Button("Copy Issue", action: onCopy)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderedProminent)
            }
            Button("Close", action: onClose)
                .buttonStyle(.bordered)
        }
        .frame(height: ExtensionBubbleMetrics.formControlHeight, alignment: .leading)
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
            Toggle(
                "Turn On",
                isOn: Binding(get: { row.enabled }, set: onEnabled)
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        case .unavailable:
            EmptyView()
        }
    }
}
