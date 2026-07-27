import Foundation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let bubblePlacement = "settings.bubblePlacement"
    }

    var bubblePlacement: BubblePlacement {
        didSet {
            guard oldValue != bubblePlacement else { return }
            UserDefaults.standard.set(bubblePlacement.rawValue, forKey: Keys.bubblePlacement)
            PetPanelController.shared.refreshContent()
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.bubblePlacement) ?? BubblePlacement.top.rawValue
        bubblePlacement = BubblePlacement(rawValue: raw) ?? .top
    }
}
