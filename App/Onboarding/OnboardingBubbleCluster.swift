import AiboCore
import SwiftUI

/// Welcome bubble; Skip / Continue hang 8pt below and are not part of layout height
/// so vertical centering is against the bubble, not the pills.
struct OnboardingBubbleCluster: View {
    let item: StatusBubbleItem
    let placement: BubblePlacement
    var showsArrow: Bool = true
    var animates: Bool = true
    /// See `StatusBubble.reservesArrowSlot`.
    var reservesArrowSlot: Bool = false
    var glassStyle: BubbleGlassStyle
    var glassTint: Color?

    @Bindable private var onboarding = OnboardingController.shared

    var body: some View {
        bubble
            .background(alignment: .bottomTrailing) {
                if hasActionPills {
                    actionPills
                        .offset(y: OnboardingChrome.actionPillsStackHeight)
                }
            }
    }

    private var hasActionPills: Bool {
        onboarding.showsSkip || onboarding.showsContinueHint
    }

    @ViewBuilder
    private var actionPills: some View {
        HStack(spacing: OnboardingChrome.buttonSpacing) {
            if onboarding.showsSkip {
                OnboardingPillButton(
                    title: String(localized: "Skip"),
                    kind: .skip,
                    glassStyle: glassStyle,
                    glassTint: glassTint,
                    action: { onboarding.skip() }
                )
            }
            if onboarding.showsContinueHint {
                OnboardingPillButton(
                    title: onboarding.continueHintTitle,
                    kind: .continueHint,
                    glassStyle: glassStyle,
                    glassTint: glassTint,
                    action: { onboarding.advance() }
                )
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let onActivate: (() -> Void)? = onboarding.bubbleTapAdvances
            ? { onboarding.advance() }
            : nil
        if animates {
            AnimatedStatusBubble(
                item: item,
                placement: placement,
                showsArrow: showsArrow,
                reservesArrowSlot: reservesArrowSlot,
                onActivate: onActivate,
                glassStyle: glassStyle,
                glassTint: glassTint
            )
        } else {
            StatusBubble(
                item: item,
                placement: placement,
                showsArrow: showsArrow,
                reservesArrowSlot: reservesArrowSlot,
                onActivate: onActivate,
                glassStyle: glassStyle,
                glassTint: glassTint
            )
        }
    }
}

private struct OnboardingPillButton: View {
    enum Kind {
        case skip
        case continueHint
    }

    let title: String
    let kind: Kind
    var glassStyle: BubbleGlassStyle
    var glassTint: Color?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let prefersLightLabel = StatusBubble.prefersLightLabel(
            tint: glassTint,
            style: glassStyle,
            colorScheme: colorScheme
        )
        let ink = prefersLightLabel ? Color.white : Color.black
        Text(title)
            .font(.system(size: OnboardingChrome.buttonFontSize))
            .foregroundStyle(kind == .skip ? ink.opacity(0.45) : ink)
            .padding(.horizontal, 10)
            .frame(height: OnboardingChrome.buttonHeight)
            .background { pillBackground }
            .environment(
                \.backgroundProminence,
                prefersLightLabel ? .increased : .standard
            )
            .contentShape(Capsule())
            .highPriorityGesture(TapGesture().onEnded(action))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var pillBackground: some View {
        // Same glass + behind-fill as the status bubble; keep glyphs outside glassEffect.
        let shape = Capsule()
        if glassStyle == .identity {
            shape.fill(StatusBubble.behindFill(style: glassStyle, tint: glassTint))
        } else {
            shape
                .fill(Color.clear)
                .glassEffect(
                    StatusBubble.configuredGlass(style: glassStyle, tint: glassTint),
                    in: shape
                )
                .background {
                    shape.fill(StatusBubble.behindFill(style: glassStyle, tint: glassTint))
                }
        }
    }
}
