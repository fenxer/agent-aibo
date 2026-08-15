import AppKit
import SwiftUI

/// App-wide color scheme preference.
enum AppThemeMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Auto")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// Settings radio order: Light / Dark / Auto.
    static var settingsCases: [AppThemeMode] { [.light, .dark, .system] }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: system
        }
    }

    /// `nil` means inherit the system appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
