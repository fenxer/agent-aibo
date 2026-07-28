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
        static let webhookEnabled = "settings.webhookEnabled"
        static let webhookPort = "settings.webhookPort"
        static let webhookSecretAccount = "webhook.sharedSecret"
    }

    static let defaultWebhookPort: UInt16 = 8787

    var bubblePlacement: BubblePlacement {
        didSet {
            guard oldValue != bubblePlacement else { return }
            UserDefaults.standard.set(bubblePlacement.rawValue, forKey: Keys.bubblePlacement)
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

        webhookEnabled = UserDefaults.standard.bool(forKey: Keys.webhookEnabled)
        let storedPort = UserDefaults.standard.integer(forKey: Keys.webhookPort)
        if storedPort > 0, storedPort <= Int(UInt16.max) {
            webhookPort = UInt16(storedPort)
        } else {
            webhookPort = Self.defaultWebhookPort
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
