import AiboCore
import CryptoKit
import Foundation

public enum WebhookRequestHandler {
    public struct Result: Equatable, Sendable {
        public var statusCode: Int
        public var delivery: WebhookDelivery?

        public init(statusCode: Int, delivery: WebhookDelivery? = nil) {
            self.statusCode = statusCode
            self.delivery = delivery
        }
    }

    public static let path = "/webhook"

    public static func handle(
        request: HTTPRequest,
        secret: String,
        idCache: inout WebhookIDCache,
        now: Date = Date()
    ) -> Result {
        guard request.method.uppercased() == "POST" else {
            return Result(statusCode: 405)
        }
        guard request.path == path else {
            return Result(statusCode: 404)
        }
        guard WebhookSignature.isValid(
            body: request.body,
            signatureHeader: request.header("X-Webhook-Signature"),
            secret: secret
        ) else {
            return Result(statusCode: 401)
        }

        let deliveryID = request.header("X-Webhook-ID")
            ?? fallbackID(for: request.body)
        if idCache.containsOrInsert(deliveryID) {
            return Result(statusCode: 200)
        }

        let parsed = WebhookMessageFormatter.parse(from: request.body)
        return Result(
            statusCode: 200,
            delivery: WebhookDelivery(
                id: deliveryID,
                source: parsed.source,
                displayText: parsed.displayText,
                receivedAt: now
            )
        )
    }

    private static func fallbackID(for body: Data) -> String {
        // Stable-ish id when the sender omits X-Webhook-ID.
        let digest = SHA256.hash(data: body)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "body:\(hex.prefix(32))"
    }
}
