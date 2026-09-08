import AiboCore
import Foundation

/// Desktop onboarding chrome metrics. Keep in sync with `AiboPanelController` height estimates.
enum OnboardingChrome {
    static let buttonHeight: CGFloat = 24
    static let buttonFontSize: CGFloat = 12
    static let buttonSpacing: CGFloat = 8
    static let bubbleToButtonsSpacing: CGFloat = 8
    /// Skip / Continue sit under the bubble; vertical centering uses the bubble only.
    static var actionPillsStackHeight: CGFloat { bubbleToButtonsSpacing + buttonHeight }
    /// Gap between stacked onboarding bubbles (Cursor demo + copy).
    static let stackedBubbleSpacing: CGFloat = 8
    static let projectName = "aibo-project"
    static let companionName = "Poli"
    static let cursorDemoProjectName = "example-project"
    static let cursorDemoModelName = "model-name"
    static let cursorDemoBubbleID = "onboarding:demo-cursor"
    /// Hook setup lists only the agents in the mock (not DeepSeek).
    static let hookSetupAgents: [AgentKind] = [.cursor, .codex]
    /// Aibo center in `visibleFrame` (0,0 = bottom-leading). Slightly left and down of center.
    static let aiboCenterXPercent: Double = 0.40
    static let aiboCenterYPercent: Double = 0.40

    static let chooseListRowHeight: CGFloat = 34
    static let chooseFieldHeight: CGFloat = 28
    static let chooseListCornerRadius: CGFloat = 10
    static let chooseFieldCornerRadius: CGFloat = 8
    static let chooseSolidButtonCornerRadius: CGFloat = 8
    static let chooseAfterBodySpacing: CGFloat = 10
    static let chooseVisitLinkHeight: CGFloat = 16
    static let chooseFooterLeadingPadding: CGFloat = 12
    /// Gap between the hook agent list and the Continue / Skip group.
    static let hookFooterGroupSpacing: CGFloat = 4
    /// One-line settings-style slider row (label + slider + value).
    static let chooseFormRowHeight: CGFloat = 36
    /// Slack so the panel is never shorter than the cluster; a short panel
    /// recenters the aibo against a taller bubble and the sprite jumps up.
    static let chooseLayoutSlack: CGFloat = 28

    /// Extra height inside the bubble after the body copy (list / URL / name field).
    static func chooseAiboExtraHeight(phase: OnboardingChoosePhase, hasError: Bool) -> CGFloat {
        let error: CGFloat = hasError ? 18 : 0
        switch phase {
        case .options:
            return chooseAfterBodySpacing + chooseListRowHeight * 3 + chooseLayoutSlack + error
        case .petdexInput:
            return chooseAfterBodySpacing
                + chooseListRowHeight * 3
                + 16
                + chooseFieldHeight
                + 8
                + chooseVisitLinkHeight
                + chooseLayoutSlack
                + error
        case .naming:
            return chooseAfterBodySpacing
                + 10
                + chooseFieldHeight
                + 8
                + chooseFormRowHeight * 2
                + 10
                + 8
                + chooseFieldHeight
                + chooseLayoutSlack
                + error
        }
    }

    static func agentHookExtraHeight(hasError: Bool) -> CGFloat {
        let error: CGFloat = hasError ? 18 : 0
        return chooseAfterBodySpacing
            + chooseListRowHeight * 3
            + hookFooterGroupSpacing
            + 8
            + chooseVisitLinkHeight
            + chooseLayoutSlack
            + error
    }
}

/// Sub-states of the choose-aibo step. One tour step; the idle clip stays put.
enum OnboardingChoosePhase: String, Equatable, Sendable {
    case options
    case petdexInput
    case naming
}

/// Ordered tour steps. Later scenes append cases; the last step still advances by finishing.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case chooseAibo
    case success
    case bubbleStatus
    case cursorExample
    case agentHook
    case wrapUp
}

extension OnboardingStep {
    var bubbleID: String { "onboarding:\(rawValue)" }

    /// Looped clip for this step. Not the live hook/drag mapping.
    var sprite: PetdexSpriteState {
        switch self {
        case .welcome, .wrapUp:
            // Arm-wave clip (`clips/waving.png`, 4 frames). Distinct from
            // `.waiting` (hair-fidget / approval pose).
            .waving
        case .chooseAibo, .agentHook:
            .idle
        case .success:
            .jumping
        case .bubbleStatus, .cursorExample:
            .review
        }
    }

    /// Welcome / success / bubble-status / Cursor stack / wrap-up: tap the bubble to continue.
    var advancesOnBubbleTap: Bool {
        switch self {
        case .welcome, .success, .bubbleStatus, .cursorExample, .wrapUp:
            true
        case .chooseAibo, .agentHook:
            false
        }
    }

    /// Last step is already the door; Skip would look like bailing out.
    var showsSkipPill: Bool { self != .wrapUp }

    var continueHintTitle: String {
        switch self {
        case .wrapUp:
            String(localized: "Welcome")
        default:
            String(localized: "Click bubble to continue")
        }
    }

    var bodyText: String {
        switch self {
        case .welcome:
            String(
                localized: "Hello, welcome to Aibo.\nAibo is a desktop pet-style app that displays local Agent hook information and remote Webhook information."
            )
        case .chooseAibo:
            String(
                localized: "Aibo supports local static images (.png), or Codex-compatible desktop pet formats (spritesheet + pet.json)."
            )
        case .success:
            String(
                localized: "Nice.\nYou can fine-tune the details later in Settings."
            )
        case .bubbleStatus:
            String(localized: "Aibo mainly uses bubbles to show status.")
        case .cursorExample:
            String(localized: "For example, that's Cursor's status above. ↑")
        case .agentHook:
            String(localized: "Let's set up the local Agent hook now!")
        case .wrapUp:
            String(
                localized: "Nice, you're all set.\nYou can open Settings later to explore more!"
            )
        }
    }

    static var namingBodyText: String {
        String(localized: "Loaded successfully. Give your new aibo a name.")
    }
}
