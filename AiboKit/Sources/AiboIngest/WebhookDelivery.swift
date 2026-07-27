import Foundation

public struct WebhookDelivery: Sendable, Equatable {
    public var id: String
    public var source: String
    public var displayText: String
    public var receivedAt: Date

    public init(
        id: String,
        source: String = "Webhook",
        displayText: String,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.displayText = displayText
        self.receivedAt = receivedAt
    }
}
