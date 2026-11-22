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

    @ObservationIgnored private var isApplyingRemoteSync = false

    var config: MouseShakeConfig {
        didSet {
            persist()
            if AppProcessRole.isSettings, !isApplyingRemoteSync {
                SettingsProcessClient.shared.sendCommand(.debugMouseShakeConfigChanged(config))
            }
        }
    }

    private init() {
        config = Self.load() ?? MouseShakeConfig()
    }

    func applyRemoteConfig(_ config: MouseShakeConfig) {
        isApplyingRemoteSync = true
        defer { isApplyingRemoteSync = false }
        self.config = config
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
