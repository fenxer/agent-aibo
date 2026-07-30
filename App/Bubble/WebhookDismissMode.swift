import Foundation

/// How remote webhook bubbles leave the stack.
enum WebhookDismissMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    /// User clicks / taps the bubble.
    case onClick
    /// Automatically after `webhookAutoDismissSeconds`.
    case afterSeconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onClick: String(localized: "Click to Dismiss")
        case .afterSeconds: String(localized: "After N Seconds")
        }
    }
}
