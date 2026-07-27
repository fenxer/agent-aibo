import SwiftUI

struct StatusBubble: View {
    let text: String
    let placement: BubblePlacement
    /// Only the bubble nearest the pet keeps the popover arrow.
    var showsArrow: Bool = true

    private let arrowHeight: CGFloat = 6
    private let arrowWidth: CGFloat = 10
    private let cornerRadius: CGFloat = 12

    var body: some View {
        let edge = placement.arrowEdge
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(showsArrow ? Edge.Set(edge) : [], arrowHeight)
            .background {
                bubbleBackground(edge: edge)
            }
            // Cap width; pin content toward the pet so short copy doesn't float
            // in the middle of a bubbleMaxWidth-sized panel slot.
            .frame(maxWidth: 220, alignment: frameAlignment)
    }

    @ViewBuilder
    private func bubbleBackground(edge: Edge) -> some View {
        if showsArrow {
            let shape = PopoverBubbleShape(
                arrowEdge: edge,
                cornerRadius: cornerRadius,
                arrowWidth: arrowWidth,
                arrowHeight: arrowHeight
            )
            // Keep text outside glassEffect — Liquid Glass foreground treatment
            // over glyphs causes heavy aliasing on a transparent NSPanel.
            shape
                .fill(Color.white.opacity(0.2))
                .background {
                    Color.clear.glassEffect(.clear, in: shape)
                }
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(Color.white.opacity(0.2))
                .background {
                    Color.clear.glassEffect(.clear, in: shape)
                }
        }
    }

    /// Side closest to the pet — left bubble pins trailing, right pins leading.
    private var frameAlignment: Alignment {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
    }
}

#Preview("top") {
    StatusBubble(text: "Cursor is thinking…", placement: .top)
        .padding(40)
        .background(Color.secondary.opacity(0.25))
}

#Preview("stacked") {
    StatusBubble(text: "Codex is waiting for you", placement: .top, showsArrow: false)
        .padding(40)
        .background(Color.secondary.opacity(0.25))
}
