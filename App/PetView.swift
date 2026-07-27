import SwiftUI

struct PetView: View {
    private let petSize: CGFloat = 96

    var body: some View {
        Image("DefaultPet")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: petSize, height: petSize)
            .accessibilityLabel(String(localized: "Desktop pet"))
    }
}

#Preview {
    PetView()
        .padding()
}
