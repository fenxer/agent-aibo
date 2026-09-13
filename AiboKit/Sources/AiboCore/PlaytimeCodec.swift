import CryptoKit
import Foundation

/// HMAC-SHA256 envelope for a playtime snapshot. Key is compiled in; casual edits fail verify.
public enum PlaytimeCodec {
    public static func encode(_ snapshot: PlaytimeSnapshot) throws -> Data {
        let payload = try encodePayload(snapshot)
        let envelope = Envelope(snapshot: snapshot, hmac: sign(payload))
        return try encoder.encode(envelope)
    }

    /// `nil` when the bytes are garbage or the HMAC does not match.
    public static func decode(_ data: Data) -> PlaytimeSnapshot? {
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              let payload = try? encodePayload(envelope.snapshot)
        else { return nil }
        let key = SymmetricKey(data: signingKey)
        guard let mac = bytes(fromHex: envelope.hmac),
              HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: payload, using: key)
        else { return nil }
        return envelope.snapshot
    }

    private struct Envelope: Codable {
        var snapshot: PlaytimeSnapshot
        var hmac: String
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    /// Deters casual edits. Extracting this from the binary is accepted.
    private static let signingKey: Data = Data([
        0xA1, 0xB0, 0x70, 0xA1, 0x9E, 0xA7, 0x1E, 0xE0,
        0x5E, 0xC0, 0xDE, 0x00, 0x51, 0x67, 0x4A, 0x1B,
        0xC0, 0xFF, 0xEE, 0x42, 0x11, 0x22, 0x33, 0x44,
        0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC,
    ])

    private static func encodePayload(_ snapshot: PlaytimeSnapshot) throws -> Data {
        try encoder.encode(snapshot)
    }

    private static func sign(_ payload: Data) -> String {
        let key = SymmetricKey(data: signingKey)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(fromHex hex: String) -> Data? {
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
