import AiboCore
import AiboIngest
import Foundation

/// Process-wide role and startup metadata configured once in `AiboMain.main()`.
enum AppProcessRole {
    nonisolated(unsafe) private(set) static var current: SettingsProcessRole = .main
    nonisolated(unsafe) private(set) static var launchedExecutable: LaunchedExecutable?
    nonisolated(unsafe) private(set) static var settingsPipeFDs: (readFD: Int32, writeFD: Int32)?

    static var isMain: Bool { current == .main }
    static var isSettings: Bool { current == .settings }

    /// Must run once at process entry before AppKit, SwiftUI, or any singleton initializes.
    static func bootstrapFromCommandLine() {
        current = SettingsProcessRole.parse(arguments: CommandLine.arguments)
        switch current {
        case .main:
            if let executableURL = Bundle.main.executableURL {
                launchedExecutable = LaunchedExecutable(executableURL: executableURL)
            }
        case .settings:
            settingsPipeFDs = SettingsPipeChannel.captureStandardIOForChild()
        }
    }
}
