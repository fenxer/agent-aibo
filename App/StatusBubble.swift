import SwiftUI

struct StatusBubble: View {
    let text: String
    let placement: BubblePlacement

    private let arrowHeight: CGFloat = 9

    var body: some View {
        let edge = placement.arrowEdge
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(Edge.Set(edge), arrowHeight)
            .glassEffect(.regular, in: PopoverBubbleShape(arrowEdge: edge, arrowHeight: arrowHeight))
            .frame(maxWidth: 220)
    }
}

#Preview("top") {
    StatusBubble(text: "Cursor is thinking…", placement: .top)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("left") {
    StatusBubble(text: "Cursor is using Shell", placement: .left)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
