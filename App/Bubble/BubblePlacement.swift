import SwiftUI
import AiboCore

extension BubblePlacement {
    /// Settings → General → Position. App catalog only — AiboCore must not localize UI.
    /// Webhook connectivity already owns the key `Down` (“已断开”).
    var title: String {
        switch self {
        case .top: String(localized: "Up")
        case .bottom: String(localized: "position.down", defaultValue: "Down")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }

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
