import AiboCore
import SwiftUI

/// Cursor / Codex hook install list inside the onboarding bubble.
struct OnboardingAgentHookContent: View {
    var ink: Color

    @Bindable private var onboarding = OnboardingController.shared
    @Bindable private var runtime = AiboRuntime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: OnboardingChrome.hookFooterGroupSpacing) {
                VStack(spacing: 0) {
                    ForEach(Array(OnboardingChrome.hookSetupAgents.enumerated()), id: \.element) { index, agent in
                        if index > 0 {
                            divider
                        }
                        hookRow(agent)
                    }
                }
                .background(listCardFill)

                ChooseHookFooterRow(
                    title: hasInstalledListedHook
                        ? String(localized: "Continue")
                        : String(localized: "Skip, set in the menu later"),
                    ink: ink,
                    action: { onboarding.completeAgentHookSetup() }
                )
                .background(listCardFill)
            }

            Text(String(localized: "More Agents will be supported later."))
                .font(.system(size: 12))
                .foregroundStyle(ink.opacity(0.6))
                .padding(.leading, OnboardingChrome.chooseFooterLeadingPadding)

            if let error = onboarding.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, OnboardingChrome.chooseFooterLeadingPadding)
            }
        }
        .onAppear { runtime.refreshHostAppPresence() }
    }

    private var listCardFill: some View {
        RoundedRectangle(
            cornerRadius: OnboardingChrome.chooseListCornerRadius,
            style: .continuous
        )
        .fill(ink.opacity(0.06))
    }

    private var hasInstalledListedHook: Bool {
        OnboardingChrome.hookSetupAgents.contains { runtime.isHookInstalled(for: $0) }
    }

    private func hookRow(_ agent: AgentKind) -> some View {
        let installed = runtime.isHookInstalled(for: agent)
        let hostAppInstalled = runtime.isHostAppInstalled(for: agent)
        return ChooseHookFooterRow(
            title: StatusCopy.displayName(agent),
            ink: ink,
            showsInstalled: installed,
            showsMissingHostApp: !installed && !hostAppInstalled,
            enabled: !installed && hostAppInstalled,
            action: { onboarding.installTourHook(agent) }
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(ink.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct ChooseHookFooterRow: View {
    let title: String
    let ink: Color
    var showsInstalled: Bool = false
    var showsMissingHostApp: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(showsMissingHostApp ? ink.opacity(0.45) : ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if showsInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(String(localized: "Installed"))
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if showsMissingHostApp {
                Text(String(localized: "Not Installed on This Mac"))
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: OnboardingChrome.chooseListRowHeight)
        .contentShape(Rectangle())
        .allowsHitTesting(enabled)
        .highPriorityGesture(TapGesture().onEnded {
            action()
        })
        .accessibilityAddTraits(enabled ? .isButton : [])
        .accessibilityLabel(
            showsInstalled
                ? "\(title), \(String(localized: "Installed"))"
                : (showsMissingHostApp
                    ? "\(title), \(String(localized: "Not Installed on This Mac"))"
                    : title)
        )
    }
}
