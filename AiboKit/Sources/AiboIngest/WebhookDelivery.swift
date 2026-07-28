import Foundation

public struct WebhookDelivery: Sendable, Equatable {
    public var id: String
    public var source: String
    /// Raw status for the webhook capsule, when present.
    public var status: String?
    /// Summary / message body shown beside the capsule.
    public var summary: String?
    /// Combined line for receive log.
    public var displayText: String
    public var receivedAt: Date

    public init(
        id: String,
        source: String = "Webhook",
        status: String? = nil,
        summary: String? = nil,
        displayText: String,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.status = status
        self.summary = summary
        self.displayText = displayText
        self.receivedAt = receivedAt
    }
}
