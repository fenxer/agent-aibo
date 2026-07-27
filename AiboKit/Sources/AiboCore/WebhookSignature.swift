import CryptoKit
import Foundation

public enum WebhookSignature {
    /// Verifies `X-Webhook-Signature: sha256=<hex>` against the raw body.
    public static func isValid(body: Data, signatureHeader: String?, secret: String) -> Bool {
        guard let signatureHeader, !secret.isEmpty else { return false }
        let prefix = "sha256="
        guard signatureHeader.lowercased().hasPrefix(prefix) else { return false }
        let hex = String(signatureHeader.dropFirst(prefix.count))
        guard let expected = data(fromHex: hex) else { return false }

        let key = SymmetricKey(data: Data(secret.utf8))
        return HMAC<SHA256>.isValidAuthenticationCode(expected, authenticating: body, using: key)
    }

    public static func sign(body: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return "sha256=\(Data(mac).map { String(format: "%02x", $0) }.joined())"
    }

    private static func data(fromHex hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
