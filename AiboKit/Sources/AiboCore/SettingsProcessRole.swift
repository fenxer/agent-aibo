import Foundation

/// Execution role for the single `aibo` executable.
///
/// The main app launches itself again with `--role=settings` so the Settings UI
/// lives in a short-lived process whose memory (and system helpers such as
/// AutoFill) returns to the OS when the window closes.
public enum SettingsProcessRole: String, Sendable, Equatable {
    case main
    case settings

    public static let roleArgumentPrefix = "--role="
    public static let settingsArgument = "--role=settings"

    public static func parse(arguments: [String]) -> SettingsProcessRole {
        for argument in arguments.dropFirst() {
            guard argument.hasPrefix(roleArgumentPrefix) else { continue }
            let raw = String(argument.dropFirst(roleArgumentPrefix.count))
            if let role = SettingsProcessRole(rawValue: raw) {
                return role
            }
        }
        return .main
    }
}
