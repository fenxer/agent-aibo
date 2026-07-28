import SwiftUI

/// Liquid Glass variant for the status bubble background.
enum BubbleGlassStyle: String, CaseIterable, Identifiable, Sendable, Hashable {
    case clear
    case regular
    case identity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: String(localized: "Clear")
        case .regular: String(localized: "Regular")
        case .identity: String(localized: "Translucent")
        }
    }

    var glass: Glass {
        switch self {
        case .clear: .clear
        case .regular: .regular
        case .identity: .identity
        }
    }
}
