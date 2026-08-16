import AiboCore
import Foundation

@MainActor
@Observable
final class AiboActionSettings {
    static let shared = AiboActionSettings()

    private enum Keys {
        static let mapping = "settings.aiboActionMapping"
    }

    private(set) var overrides: [String: String]

    private init() {
        overrides = Self.load()
    }

    func sprite(for action: AiboUserAction) -> PetdexSpriteState {
        AiboActionMapping.resolve(action, overrides: overrides)
    }

    func setSprite(_ sprite: PetdexSpriteState, for action: AiboUserAction) {
        let defaultValue = AiboActionMapping.defaultSprite(for: action)
        var next = overrides
        if sprite == defaultValue {
            next.removeValue(forKey: action.rawValue)
        } else {
            next[action.rawValue] = sprite.rawValue
        }
        guard next != overrides else { return }
        overrides = next
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(overrides, forKey: Keys.mapping)
    }

    private static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: Keys.mapping) as? [String: String] ?? [:]
    }
}

extension AiboUserAction {
    var settingsTitle: String {
        switch self {
        case .dragLeft: String(localized: "Drag Left")
        case .dragRight: String(localized: "Drag Right")
        }
    }
}

extension PetdexSpriteState {
    var localizedTitle: String {
        switch self {
        case .idle: String(localized: "Idle")
        case .runningRight: String(localized: "Run Right")
        case .runningLeft: String(localized: "Run Left")
        case .waving: String(localized: "Waving")
        case .jumping: String(localized: "Jumping")
        case .failed: String(localized: "Failed")
        case .waiting: String(localized: "Waiting")
        case .running: String(localized: "Running")
        case .review: String(localized: "Review")
        }
    }
}
