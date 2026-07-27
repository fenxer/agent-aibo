import AiboIngest
import Foundation
import Security

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let bubblePlacement = "settings.bubblePlacement"
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
}
