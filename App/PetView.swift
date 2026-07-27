import SwiftUI

struct PetView: View {
    var bubbleItems: [StatusBubbleItem] = []
    var placement: BubblePlacement = .top
    private let petSize: CGFloat = 96
    private let stackSpacing: CGFloat = 4
    private let petBubbleSpacing: CGFloat = 6

    var body: some View {
        Group {
            if bubbleItems.isEmpty {
                petImage
            } else {
                positionedContent
            }
        }
        .padding(8)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }

    @ViewBuilder
    private var positionedContent: some View {
        switch placement {
        case .top:
            VStack(spacing: petBubbleSpacing) {
                bubbleStack(nearPetIndex: bubbleItems.count - 1)
                petImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .bottom:
            VStack(spacing: petBubbleSpacing) {
                petImage
                // Oldest nearest pet (arrow); newer grow downward.
                bubbleStack(items: bubbleItems.reversed(), nearPetIndex: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .left:
            HStack(spacing: 0) {
                bubbleStack(nearPetIndex: bubbleItems.count - 1)
                petImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case .right:
            HStack(spacing: 0) {
                petImage
                bubbleStack(nearPetIndex: bubbleItems.count - 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// `bubbleItems` are newest-first; arrow sits on the bubble nearest the pet.
    @ViewBuilder
    private func bubbleStack(nearPetIndex: Int) -> some View {
        bubbleStack(items: bubbleItems, nearPetIndex: nearPetIndex)
    }

    @ViewBuilder
    private func bubbleStack(items: [StatusBubbleItem], nearPetIndex: Int) -> some View {
        VStack(spacing: stackSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                StatusBubble(
                    text: item.text,
                    placement: placement,
                    showsArrow: index == nearPetIndex
                )
            }
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

#Preview("stack above") {
    PetView(
        bubbleItems: [
            StatusBubbleItem(id: "1", text: "Codex is waiting for you", lastEventAt: .now),
            StatusBubbleItem(id: "2", text: "Cursor is thinking…", lastEventAt: .now.addingTimeInterval(-1)),
        ],
        placement: .top
    )
}

#Preview("left") {
    PetView(
        bubbleItems: [
            StatusBubbleItem(id: "1", text: "Cursor is using Shell", lastEventAt: .now),
        ],
        placement: .left
    )
}
