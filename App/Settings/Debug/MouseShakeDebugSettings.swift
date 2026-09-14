#if DEBUG
import AiboCore
import Foundation

/// DEBUG tunables for the mouse-shake dodge. Release always uses
/// `MouseShakeConfig()` defaults.
@MainActor
@Observable
final class MouseShakeDebugSettings {
    static let shared = MouseShakeDebugSettings()

    private static let defaultsKey = "debug.mouseShake.config"

    var config: MouseShakeConfig {
        didSet { persist() }
    }

    private init() {
        config = Self.load() ?? MouseShakeConfig()
    }

    func reset() {
        config = MouseShakeConfig()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func load() -> MouseShakeConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MouseShakeConfig.self, from: data)
    }
}
#endif
