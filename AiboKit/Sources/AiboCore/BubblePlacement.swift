import Foundation

/// Where the status bubble sits relative to the aibo image.
public enum BubblePlacement: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case top
    case bottom
    case left
    case right

    public var id: String { rawValue }
}
