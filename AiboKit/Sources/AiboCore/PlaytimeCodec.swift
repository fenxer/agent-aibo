import CryptoKit
import Foundation

enum PlaytimeHMAC {
    /// Deters casual edits. Extracting this from the binary is accepted.
    static let signingKey: Data = Data([
        0xA1, 0xB0, 0x70, 0xA1, 0x9E, 0xA7, 0x1E, 0xE0,
        0x5E, 0xC0, 0xDE, 0x00, 0x51, 0x67, 0x4A, 0x1B,
        0xC0, 0xFF, 0xEE, 0x42, 0x11, 0x22, 0x33, 0x44,
        0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC,
    ])

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func hexMAC(for payload: Data) -> String {
        let key = SymmetricKey(data: signingKey)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(payload: Data, hex: String) -> Bool {
        let key = SymmetricKey(data: signingKey)
        guard let mac = bytes(fromHex: hex) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: payload, using: key)
    }

    static func bytes(fromHex hex: String) -> Data? {
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

/// HMAC-SHA256 envelope for a playtime snapshot. Key is compiled in; casual edits fail verify.
public enum PlaytimeCodec {
    public static func encode(_ snapshot: PlaytimeSnapshot) throws -> Data {
        let payload = try PlaytimeHMAC.encoder.encode(snapshot)
        let envelope = Envelope(snapshot: snapshot, hmac: PlaytimeHMAC.hexMAC(for: payload))
        return try PlaytimeHMAC.encoder.encode(envelope)
    }

    /// `nil` when the bytes are garbage or the HMAC does not match.
    public static func decode(_ data: Data) -> PlaytimeSnapshot? {
        guard let envelope = try? PlaytimeHMAC.decoder.decode(Envelope.self, from: data),
              let payload = try? PlaytimeHMAC.encoder.encode(envelope.snapshot),
              PlaytimeHMAC.isValid(payload: payload, hex: envelope.hmac)
        else { return nil }
        return envelope.snapshot
    }

    private struct Envelope: Codable {
        var snapshot: PlaytimeSnapshot
        var hmac: String
    }
}

/// Same HMAC as the Keychain ledger; lives in Application Support because days are unbounded.
public enum PlaytimeDailyCodec {
    public static func encode(_ book: PlaytimeDailyBook) throws -> Data {
        let payload = try PlaytimeHMAC.encoder.encode(book)
        let envelope = Envelope(book: book, hmac: PlaytimeHMAC.hexMAC(for: payload))
        return try PlaytimeHMAC.encoder.encode(envelope)
    }

    public static func decode(_ data: Data) -> PlaytimeDailyBook? {
        guard let envelope = try? PlaytimeHMAC.decoder.decode(Envelope.self, from: data),
              let payload = try? PlaytimeHMAC.encoder.encode(envelope.book),
              PlaytimeHMAC.isValid(payload: payload, hex: envelope.hmac)
        else { return nil }
        return envelope.book
    }

    private struct Envelope: Codable {
        var book: PlaytimeDailyBook
        var hmac: String
    }
}
