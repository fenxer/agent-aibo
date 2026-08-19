import Foundation

/// Where the status bubble sits relative to the aibo image.
public enum BubblePlacement: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case top
    case bottom
    case left
    case right

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .top: String(localized: "Up")
        case .bottom: String(localized: "Down")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }
}
