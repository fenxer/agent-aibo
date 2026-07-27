import Foundation

/// One inbound notification kept in the receive log.
public struct ReceiveLogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var receivedAt: Date
    /// Human-readable sender / channel label (e.g. Webhook, Cloudflare, Debug).
    public var source: String
    public var message: String
    public var deliveryID: String?

    public init(
        id: String = UUID().uuidString,
        receivedAt: Date = Date(),
        source: String,
        message: String,
        deliveryID: String? = nil
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.source = source
        self.message = message
        self.deliveryID = deliveryID
    }
}
