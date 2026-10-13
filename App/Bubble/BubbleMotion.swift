import AiboCore
import Pow
import SwiftUI

extension EnvironmentValues {
    /// Tear down `glassEffect` while Pow poof runs. Active Liquid Glass is an
    /// `NSGlassEffectView` that ignores SwiftUI opacity and composites above
    /// the cartoon cloud.
    @Entry var suppressBubbleGlass: Bool = false
}

/// Flipped on for the removal transition so glass unmounts before poof frames.
private struct BubbleGlassSuppression: ViewModifier {
    var isSuppressed: Bool

    func body(content: Content) -> some View {
        content.environment(\.suppressBubbleGlass, isSuppressed)
    }
}

/// Shared motion for status-bubble insert / remove.
enum BubbleMotion {
    /// Snappy spring with a little overshoot.
    static let appear: Animation = .spring(response: 0.28, dampingFraction: 0.68)

    /// Matches Pow `.movingParts.poof` (0.4s linear).
    static let disappear: Animation = .linear(duration: 0.4)

    /// Drop glass, then play the cartoon cloud. Insertion stays identity so a
    /// remount (inspect, phase change) does not look like a dismiss.
    static var removal: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: AnyTransition.modifier(
                active: BubbleGlassSuppression(isSuppressed: true),
                identity: BubbleGlassSuppression(isSuppressed: false)
            )
            .combined(with: .movingParts.poof)
        )
    }

    /// Start offset: approach the final seat from the opposite direction.
    /// SwiftUI Y grows downward, so “from below” is a positive height.
    static func appearOffset(for placement: BubblePlacement) -> CGSize {
        let distance: CGFloat = 18
        switch placement {
        case .left: return CGSize(width: distance, height: 0)
        case .right: return CGSize(width: -distance, height: 0)
        case .top: return CGSize(width: 0, height: distance)
        case .bottom: return CGSize(width: 0, height: -distance)
        }
    }
}

/// Fade, scale, and a short slide into the seat the panel has already committed.
///
/// The panel grows on the next turn. Starting this spring before that frame
/// lands paints the card in the old window, then it teleports. Wait until the
/// growth pass bumps `frameGrowthEpoch`, and yield once more so the spring is
/// not inside the layout transaction (that collapses the NSPanel).
struct BubbleAppearMotion: ViewModifier {
    var placement: BubblePlacement

    @State private var hasAppeared = false
    @State private var panel = AiboPanelController.shared

    func body(content: Content) -> some View {
        let offset = BubbleMotion.appearOffset(for: placement)
        content
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.88)
            .offset(
                x: hasAppeared ? 0 : offset.width,
                y: hasAppeared ? 0 : offset.height
            )
            .allowsHitTesting(hasAppeared)
            .onAppear(perform: scheduleAppear)
            .onChange(of: panel.frameGrowthEpoch) { _, _ in
                scheduleAppear()
            }
    }

    private func scheduleAppear() {
        guard !hasAppeared, !panel.isFrameGrowthPending else { return }
        Task { @MainActor in
            await Task.yield()
            guard !hasAppeared, !AiboPanelController.shared.isFrameGrowthPending else { return }
            withAnimation(BubbleMotion.appear) {
                hasAppeared = true
            }
        }
    }
}

/// Drives appear with explicit state so NSHostingView / overlay layouts
/// still animate (SwiftUI `.transition` is unreliable in those paths).
struct AnimatedStatusBubble: View {
    let item: StatusBubbleItem
    let placement: BubblePlacement
    var showsArrow: Bool = true
    /// See `StatusBubble.reservesArrowSlot`.
    var reservesArrowSlot: Bool = false
    var onActivate: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var glassStyle: BubbleGlassStyle = AppSettings.shared.bubbleGlassStyle
    var glassTint: Color? = AppSettings.shared.bubbleGlassTint

    var body: some View {
        // A real layout boundary keeps StatusBubble's internal identity
        // transition from overriding this wrapper's removal transition.
        // Group is transparent here and does not isolate the two transitions.
        ZStack {
            StatusBubble(
                item: item,
                placement: placement,
                showsArrow: showsArrow,
                reservesArrowSlot: reservesArrowSlot,
                onActivate: onActivate,
                onDismiss: onDismiss,
                glassStyle: glassStyle,
                glassTint: glassTint
            )
        }
        // Onboarding already reserves an arrow slot inside each card.
        .padding(.leading, !showsArrow && !reservesArrowSlot && placement == .right ? 8 : 0)
        .padding(.trailing, !showsArrow && !reservesArrowSlot && placement == .left ? 8 : 0)
        .modifier(BubbleAppearMotion(placement: placement))
        // Appear is explicit above; dismiss uses Pow's cartoon poof cloud.
        // Insertion must stay identity — inspect open/close used to remount
        // this view and play poof as if the bubble had been dismissed.
        // Drop glass first: `_hasActiveAppearance` makes real NSGlassEffectView,
        // which would eat the overlay if it stayed in the tree.
        .transition(BubbleMotion.removal)
    }
}
