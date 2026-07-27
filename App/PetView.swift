import SwiftUI

struct PetView: View {
    var bubbleText: String?
    var placement: BubblePlacement = .top
    private let petSize: CGFloat = 96

    var body: some View {
        Group {
            if let bubbleText {
                positionedContent(bubbleText: bubbleText)
            } else {
                petImage
            }
        }
        .padding(8)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }

    @ViewBuilder
    private func positionedContent(bubbleText: String) -> some View {
        let bubble = StatusBubble(text: bubbleText, placement: placement)

        switch placement {
        case .top:
            VStack(spacing: 6) {
                bubble
                petImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .bottom:
            VStack(spacing: 6) {
                petImage
                bubble
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .left:
            HStack(spacing: 0) {
                bubble
                petImage
            }
            // Keep the pet on the trailing edge; bubble grows away from it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case .right:
            HStack(spacing: 0) {
                petImage
                bubble
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var petImage: some View {
        Image("DefaultPet")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: petSize, height: petSize)
            .accessibilityLabel(String(localized: "Desktop pet"))
    }
}

#Preview("above") {
    PetView(bubbleText: "Cursor is thinking…", placement: .top)
}

#Preview("left") {
    PetView(bubbleText: "Cursor is using Shell", placement: .left)
}
