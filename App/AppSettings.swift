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
        static let webhookEnabled = "settings.webhookEnabled"
        static let webhookPort = "settings.webhookPort"
        static let webhookDismissMode = "settings.webhookDismissMode"
        static let webhookAutoDismissSeconds = "settings.webhookAutoDismissSeconds"
        static let webhookSecretAccount = "webhook.sharedSecret"
    }

    static let defaultWebhookPort: UInt16 = 8787
    /// Pet image size as a percentage of the base 96pt sprite. Range 0…200; default 100.
    static let defaultPetScalePercent: Double = 100
    static let petScalePercentRange: ClosedRange<Double> = 0...200
    static let defaultWebhookAutoDismissSeconds = 12
    static let webhookAutoDismissSecondsRange = 1...600

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

    private static func clampPetScalePercent(_ value: Double) -> Double {
        min(max(value, petScalePercentRange.lowerBound), petScalePercentRange.upperBound)
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
