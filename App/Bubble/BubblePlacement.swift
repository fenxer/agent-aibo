import SwiftUI
import AiboCore

extension BubblePlacement {
    /// Edge of the bubble that should show the popover arrow (toward the aibo).
    var arrowEdge: Edge {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .trailing
        case .right: .leading
        }
    }
}
