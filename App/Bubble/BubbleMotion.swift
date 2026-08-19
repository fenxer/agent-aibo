import AiboCore
import Pow
import SwiftUI

/// Shared motion for status-bubble insert / remove.
enum BubbleMotion {
    /// Snappy spring with a little overshoot.
    static let appear: Animation = .spring(response: 0.28, dampingFraction: 0.68)

    /// Matches Pow `.movingParts.poof` (0.4s linear).
    static let disappear: Animation = .linear(duration: 0.4)

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

/// Drives appear with explicit state so NSHostingView / overlay layouts
/// still animate (SwiftUI `.transition` is unreliable in those paths).
struct AnimatedStatusBubble: View {
    let item: StatusBubbleItem
    let placement: BubblePlacement
    var showsArrow: Bool = true
    var onActivate: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var glassStyle: BubbleGlassStyle = AppSettings.shared.bubbleGlassStyle
    var glassTint: Color? = AppSettings.shared.bubbleGlassTint

    @State private var hasAppeared = false

    var body: some View {
        let offset = BubbleMotion.appearOffset(for: placement)
        StatusBubble(
            item: item,
            placement: placement,
            showsArrow: showsArrow,
            onActivate: onActivate,
            onDismiss: onDismiss,
            glassStyle: glassStyle,
            glassTint: glassTint
        )
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.88)
        .offset(
            x: hasAppeared ? 0 : offset.width,
            y: hasAppeared ? 0 : offset.height
        )
        // Appear is explicit above; dismiss uses Pow's cartoon poof cloud.
        .transition(.movingParts.poof)
        .onAppear {
            guard !hasAppeared else { return }
            // Defer so the initial opacity/offset state isn't itself inside an
            // outer `withAnimation` transaction (that collapses NSPanel layout).
            Task { @MainActor in
                withAnimation(BubbleMotion.appear) {
                    hasAppeared = true
                }
            }
        }
    }
}
