import SwiftUI

struct StatusBubble: View {
    let text: String
    let placement: BubblePlacement

    private let arrowHeight: CGFloat = 6
    private let arrowWidth: CGFloat = 10

    var body: some View {
        let edge = placement.arrowEdge
        let shape = PopoverBubbleShape(
            arrowEdge: edge,
            cornerRadius: 12,
            arrowWidth: arrowWidth,
            arrowHeight: arrowHeight
        )
        // Keep text outside glassEffect — Liquid Glass foreground treatment
        // over glyphs causes heavy aliasing on a transparent NSPanel.
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(Edge.Set(edge), arrowHeight)
            .background {
                shape
                    .fill(Color.white.opacity(0.2))
                    .background {
                        Color.clear.glassEffect(.clear, in: shape)
                    }
            }
            // Cap width; pin content toward the pet so short copy doesn't float
            // in the middle of a bubbleMaxWidth-sized panel slot.
            .frame(maxWidth: 220, alignment: frameAlignment)
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

#Preview("left") {
    StatusBubble(text: "Cursor is thinking…", placement: .left)
        .padding(40)
        .background(Color.secondary.opacity(0.25))
}
