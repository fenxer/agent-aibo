import AiboIngest
import AppKit
import Foundation
import Security
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let bubblePlacement = "settings.bubblePlacement"
        static let bubbleGlassStyle = "settings.bubbleGlassStyle"
        static let bubbleGlassTint = "settings.bubbleGlassTint"
        static let petScalePercent = "settings.petScalePercent"
        static let restoreLastPetPosition = "settings.restoreLastPetPosition"
        static let petPositionXPercent = "settings.petPositionXPercent"
        static let petPositionYPercent = "settings.petPositionYPercent"
        static let musicNotesEnabled = "settings.musicNotesEnabled"
        static let customMusicNotificationNames = "settings.customMusicNotificationNames"
        static let webhookEnabled = "settings.webhookEnabled"
        static let webhookPort = "settings.webhookPort"
        static let webhookDismissMode = "settings.webhookDismissMode"
        static let webhookAutoDismissSeconds = "settings.webhookAutoDismissSeconds"
        static let settingsWindowHeight = "settings.windowHeight"
        static let webhookSecretAccount = "webhook.sharedSecret"
    }

    static let defaultWebhookPort: UInt16 = 8787
    /// Pet image size as a percentage of the base 96pt sprite. Range 0…200; default 100.
    static let defaultPetScalePercent: Double = 100
    static let petScalePercentRange: ClosedRange<Double> = 0...200
    static let defaultWebhookAutoDismissSeconds = 12
    static let webhookAutoDismissSecondsRange = 1...600

    /// Settings window content width (fixed; only height is user-resizable).
    static let settingsWindowWidth: CGFloat = 680
    static let defaultSettingsWindowHeight: CGFloat = 720
    static let settingsWindowMinHeight: CGFloat = 420

    var bubblePlacement: BubblePlacement {
        didSet {
            guard oldValue != bubblePlacement else { return }
            UserDefaults.standard.set(bubblePlacement.rawValue, forKey: Keys.bubblePlacement)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Pet sprite scale relative to the default size (`100` = 96×96 pt).
    var petScalePercent: Double {
        didSet {
            let clamped = Self.clampPetScalePercent(petScalePercent)
            if clamped != petScalePercent {
                petScalePercent = clamped
                return
            }
            guard oldValue != petScalePercent else { return }
            UserDefaults.standard.set(petScalePercent, forKey: Keys.petScalePercent)
            PetPanelController.shared.refreshContent()
        }
    }

    /// When true, the pet opens at its last screen-relative position. Default on.
    var restoreLastPetPosition: Bool {
        didSet {
            guard oldValue != restoreLastPetPosition else { return }
            UserDefaults.standard.set(restoreLastPetPosition, forKey: Keys.restoreLastPetPosition)
        }
    }

    /// Pet center X within the screen `visibleFrame`, 0…1. `nil` until the user has moved the pet.
    private(set) var savedPetCenterXPercent: Double?
    /// Pet center Y within the screen `visibleFrame`, 0…1. `nil` until the user has moved the pet.
    private(set) var savedPetCenterYPercent: Double?

    /// Overlay music-note rise effect while a known player is playing. Default on.
    var musicNotesEnabled: Bool {
        didSet {
            guard oldValue != musicNotesEnabled else { return }
            UserDefaults.standard.set(musicNotesEnabled, forKey: Keys.musicNotesEnabled)
            PetRuntime.shared.syncMusicPlaybackMonitor()
            PetPanelController.shared.refreshContent()
        }
    }

    /// Extra distributed notification names (one per line) beyond built-in Music / Spotify.
    var customMusicNotificationNames: String {
        didSet {
            guard oldValue != customMusicNotificationNames else { return }
            UserDefaults.standard.set(customMusicNotificationNames, forKey: Keys.customMusicNotificationNames)
            MusicPlaybackMonitor.shared.reloadObservers()
        }
    }

    /// Liquid Glass variant for the status bubble. Default matches prior `.clear` look.
    var bubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != bubbleGlassStyle else { return }
            UserDefaults.standard.set(bubbleGlassStyle.rawValue, forKey: Keys.bubbleGlassStyle)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Optional glass tint. `nil` means no tint (system default).
    var bubbleGlassTint: Color? {
        didSet {
            guard oldValue != bubbleGlassTint else { return }
            Self.persistTint(bubbleGlassTint)
            PetPanelController.shared.refreshContent()
        }
    }

    var webhookEnabled: Bool {
        didSet {
            guard oldValue != webhookEnabled else { return }
            UserDefaults.standard.set(webhookEnabled, forKey: Keys.webhookEnabled)
            PetRuntime.shared.syncWebhookServer()
        }
    }

    var webhookPort: UInt16 {
        didSet {
            guard oldValue != webhookPort else { return }
            UserDefaults.standard.set(Int(webhookPort), forKey: Keys.webhookPort)
            PetRuntime.shared.syncWebhookServer()
        }
    }

    /// Default `.onClick` — webhook bubbles stay until the user dismisses them.
    var webhookDismissMode: WebhookDismissMode {
        didSet {
            guard oldValue != webhookDismissMode else { return }
            UserDefaults.standard.set(webhookDismissMode.rawValue, forKey: Keys.webhookDismissMode)
        }
    }

    /// Used when `webhookDismissMode == .afterSeconds`.
    var webhookAutoDismissSeconds: Int {
        didSet {
            let clamped = Self.clampWebhookAutoDismissSeconds(webhookAutoDismissSeconds)
            if clamped != webhookAutoDismissSeconds {
                webhookAutoDismissSeconds = clamped
                return
            }
            guard oldValue != webhookAutoDismissSeconds else { return }
            UserDefaults.standard.set(webhookAutoDismissSeconds, forKey: Keys.webhookAutoDismissSeconds)
        }
    }

    private(set) var webhookSecret: String

    /// Last Settings window content height. Width stays `settingsWindowWidth`.
    private(set) var settingsWindowHeight: CGFloat

    var webhookURLString: String {
        "http://127.0.0.1:\(webhookPort)\(WebhookRequestHandler.path)"
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.bubblePlacement) ?? BubblePlacement.top.rawValue
        bubblePlacement = BubblePlacement(rawValue: raw) ?? .top

        let glassRaw = UserDefaults.standard.string(forKey: Keys.bubbleGlassStyle)
            ?? BubbleGlassStyle.clear.rawValue
        bubbleGlassStyle = BubbleGlassStyle(rawValue: glassRaw) ?? .clear
        bubbleGlassTint = Self.loadTint()

        if UserDefaults.standard.object(forKey: Keys.petScalePercent) != nil {
            petScalePercent = Self.clampPetScalePercent(
                UserDefaults.standard.double(forKey: Keys.petScalePercent)
            )
        } else {
            petScalePercent = Self.defaultPetScalePercent
        }

        if UserDefaults.standard.object(forKey: Keys.restoreLastPetPosition) != nil {
            restoreLastPetPosition = UserDefaults.standard.bool(forKey: Keys.restoreLastPetPosition)
        } else {
            restoreLastPetPosition = true
        }

        if UserDefaults.standard.object(forKey: Keys.petPositionXPercent) != nil,
           UserDefaults.standard.object(forKey: Keys.petPositionYPercent) != nil
        {
            savedPetCenterXPercent = UserDefaults.standard.double(forKey: Keys.petPositionXPercent)
            savedPetCenterYPercent = UserDefaults.standard.double(forKey: Keys.petPositionYPercent)
        } else {
            savedPetCenterXPercent = nil
            savedPetCenterYPercent = nil
        }

        if UserDefaults.standard.object(forKey: Keys.musicNotesEnabled) != nil {
            musicNotesEnabled = UserDefaults.standard.bool(forKey: Keys.musicNotesEnabled)
        } else {
            musicNotesEnabled = true
        }
        customMusicNotificationNames =
            UserDefaults.standard.string(forKey: Keys.customMusicNotificationNames) ?? ""

        webhookEnabled = UserDefaults.standard.bool(forKey: Keys.webhookEnabled)
        let storedPort = UserDefaults.standard.integer(forKey: Keys.webhookPort)
        if storedPort > 0, storedPort <= Int(UInt16.max) {
            webhookPort = UInt16(storedPort)
        } else {
            webhookPort = Self.defaultWebhookPort
        }

        let dismissRaw = UserDefaults.standard.string(forKey: Keys.webhookDismissMode)
            ?? WebhookDismissMode.onClick.rawValue
        webhookDismissMode = WebhookDismissMode(rawValue: dismissRaw) ?? .onClick

        if UserDefaults.standard.object(forKey: Keys.webhookAutoDismissSeconds) != nil {
            webhookAutoDismissSeconds = Self.clampWebhookAutoDismissSeconds(
                UserDefaults.standard.integer(forKey: Keys.webhookAutoDismissSeconds)
            )
        } else {
            webhookAutoDismissSeconds = Self.defaultWebhookAutoDismissSeconds
        }

        if UserDefaults.standard.object(forKey: Keys.settingsWindowHeight) != nil {
            settingsWindowHeight = Self.clampSettingsWindowHeight(
                CGFloat(UserDefaults.standard.double(forKey: Keys.settingsWindowHeight))
            )
        } else {
            settingsWindowHeight = Self.defaultSettingsWindowHeight
        }

        if let existing = KeychainStore.string(forAccount: Keys.webhookSecretAccount), !existing.isEmpty {
            webhookSecret = existing
        } else {
            webhookSecret = Self.makeSecret()
            try? KeychainStore.setString(webhookSecret, forAccount: Keys.webhookSecretAccount)
        }
    }

    func regenerateWebhookSecret() {
        webhookSecret = Self.makeSecret()
        try? KeychainStore.setString(webhookSecret, forAccount: Keys.webhookSecretAccount)
        PetRuntime.shared.syncWebhookServer()
    }

    func resetPetScalePercent() {
        petScalePercent = Self.defaultPetScalePercent
    }

    /// Persist pet center as fractions of the screen visible frame (resolution-independent).
    func savePetCenterRelativePosition(xPercent: Double, yPercent: Double) {
        let x = min(max(xPercent, 0), 1)
        let y = min(max(yPercent, 0), 1)
        guard savedPetCenterXPercent != x || savedPetCenterYPercent != y else { return }
        savedPetCenterXPercent = x
        savedPetCenterYPercent = y
        UserDefaults.standard.set(x, forKey: Keys.petPositionXPercent)
        UserDefaults.standard.set(y, forKey: Keys.petPositionYPercent)
    }

    func saveSettingsWindowHeight(_ height: CGFloat) {
        let clamped = Self.clampSettingsWindowHeight(height)
        guard abs(settingsWindowHeight - clamped) >= 0.5 else { return }
        settingsWindowHeight = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Keys.settingsWindowHeight)
    }

    private static func clampPetScalePercent(_ value: Double) -> Double {
        min(max(value, petScalePercentRange.lowerBound), petScalePercentRange.upperBound)
    }

    private static func clampSettingsWindowHeight(_ value: CGFloat) -> CGFloat {
        min(max(value, settingsWindowMinHeight), 4000)
    }

    private static func clampWebhookAutoDismissSeconds(_ value: Int) -> Int {
        min(max(value, webhookAutoDismissSecondsRange.lowerBound), webhookAutoDismissSecondsRange.upperBound)
    }

    private static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func persistTint(_ color: Color?) {
        guard let color else {
            UserDefaults.standard.removeObject(forKey: Keys.bubbleGlassTint)
            return
        }
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let components: [Double] = [
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent,
            rgb.alphaComponent,
        ]
        UserDefaults.standard.set(components, forKey: Keys.bubbleGlassTint)
    }

    private static func loadTint() -> Color? {
        guard let numbers = UserDefaults.standard.array(forKey: Keys.bubbleGlassTint) as? [NSNumber],
              numbers.count == 4
        else { return nil }
        return Color(
            .sRGB,
            red: numbers[0].doubleValue,
            green: numbers[1].doubleValue,
            blue: numbers[2].doubleValue,
            opacity: numbers[3].doubleValue
        )
    }
}
