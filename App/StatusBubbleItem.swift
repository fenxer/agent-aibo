import Foundation

/// One status bubble in the stacked display.
struct StatusBubbleItem: Identifiable, Equatable, Sendable {
    var id: String
    var text: String
    var lastEventAt: Date
    /// When true, a click/tap clears the bubble (used for `.failed`).
    var isDismissible: Bool = false
}
