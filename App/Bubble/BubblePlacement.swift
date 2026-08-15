import SwiftUI

/// Where the status bubble sits relative to the pet image.
enum BubblePlacement: String, CaseIterable, Identifiable, Sendable, Hashable {
    case top
    case bottom
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: String(localized: "Up")
        case .bottom: String(localized: "Down")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }

    /// Edge of the bubble that should show the popover arrow (toward the pet).
    var arrowEdge: Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .trailing
        case .right: .leading
        }
    }
}
