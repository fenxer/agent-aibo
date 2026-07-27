import SwiftUI

struct PetView: View {
    var bubbleText: String?
    private let petSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            if let bubbleText {
                GlassEffectContainer {
                    Text(bubbleText)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }
                .frame(maxWidth: 220)
            }

            Image("DefaultPet")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: petSize, height: petSize)
                .accessibilityLabel(String(localized: "Desktop pet"))
        }
        .padding(8)
        // Titlebar-less panel: make the pet content a drag handle.
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }
}

#Preview("idle") {
    PetView()
}

#Preview("thinking") {
    PetView(bubbleText: "Cursor is thinking…")
}
