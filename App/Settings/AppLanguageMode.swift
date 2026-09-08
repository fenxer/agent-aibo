import Foundation

/// App-wide UI language. Default follows the system; English and Simplified
/// Chinese can be pinned. Language names stay in their own script so a
/// mistaken switch is still recoverable.
enum AppLanguageMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    /// Settings menu order: System / English / 简体中文.
    static var settingsCases: [AppLanguageMode] { [.system, .english, .simplifiedChinese] }

    /// `nil` clears the per-app override so Foundation follows the system.
    var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .simplifiedChinese: ["zh-Hans"]
        }
    }
}
