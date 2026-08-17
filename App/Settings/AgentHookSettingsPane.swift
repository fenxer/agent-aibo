import AiboCore
import SwiftUI

struct AgentHookSettingsPane: View {
    @State private var advancedAgent: AgentKind?

    var body: some View {
        Group {
            if let advancedAgent {
                AgentHookSpriteSettingsView(agent: advancedAgent) {
                    self.advancedAgent = nil
                }
            } else {
                AgentHookSettingsRootView { agent in
                    advancedAgent = agent
                }
            }
        }
    }
}

private struct AgentHookSettingsRootView: View {
    var onOpenAgent: (AgentKind) -> Void

    @State private var runtime = AiboRuntime.shared

    private var installedAgents: [AgentKind] {
        AgentKind.allCases.filter { runtime.isHookInstalled(for: $0) }
    }

    private var uninstalledAgents: [AgentKind] {
        AgentKind.allCases.filter { !runtime.isHookInstalled(for: $0) }
    }

    var body: some View {
        Form {
            Section {
                AgentHookIntroRow()
            }

            if !installedAgents.isEmpty {
                Section {
                    ForEach(installedAgents, id: \.self) { agent in
                        AgentHookAgentRow(
                            agent: agent,
                            isInstalled: true,
                            onOpen: { onOpenAgent(agent) },
                            onInstall: { runtime.installHooks(for: agent) }
                        )
                    }
                } header: {
                    Text(String(localized: "Installed"))
                }
            }

            if !uninstalledAgents.isEmpty {
                Section {
                    ForEach(uninstalledAgents, id: \.self) { agent in
                        AgentHookAgentRow(
                            agent: agent,
                            isInstalled: false,
                            onOpen: { onOpenAgent(agent) },
                            onInstall: { runtime.installHooks(for: agent) }
                        )
                    }
                } header: {
                    Text(String(localized: "Uninstalled"))
                }
            }

            if let lastErrorMessage = runtime.lastErrorMessage {
                Section {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Agent Hook"))
    }
}

private struct AgentHookIntroRow: View {
    private let side: CGFloat = 28
    private let iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.blue)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
                        .font(.system(size: iconSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Agent Hook"))
                    .font(.body.weight(.semibold))
                Text(String(localized: "Receive local agent hook message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AgentHookAgentRow: View {
    var agent: AgentKind
    var isInstalled: Bool
    var onOpen: () -> Void
    var onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    AgentHookRowIcon(assetName: agent.settingsIconAssetName)

                    Text(StatusCopy.displayName(agent))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(String(localized: "Installed"))
                            .foregroundStyle(.green)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isInstalled {
                Button(String(localized: "Install"), action: onInstall)
            }
        }
    }
}

private struct AgentHookRowIcon: View {
    var assetName: String

    @Environment(\.colorScheme) private var colorScheme

    private let side: CGFloat = 28

    var body: some View {
        let isDark = colorScheme == .dark
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isDark ? Color.white : Color.black)
            .frame(width: side, height: side)
            .overlay {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .foregroundStyle(isDark ? Color.black : Color.white)
            }
            .accessibilityHidden(true)
    }
}

extension AgentKind {
    var settingsIconAssetName: String {
        switch self {
        case .cursor: "cursor"
        case .codex: "codex"
        case .deepseek: "deepseek"
        }
    }
}
