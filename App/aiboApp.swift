import AiboCore
import AiboIngest
import SwiftUI

@main
enum AiboMain {
    static func main() {
        AppProcessRole.bootstrapFromCommandLine()
        // AppleLanguages only — constructing AppSettings here crashes:
        // `NSApp` is still nil, and `applyAppearance` unwraps it.
        AppSettings.applyStoredLanguageAtLaunch()
        switch AppProcessRole.current {
        case .main:
            aiboApp.main()
        case .settings:
            SettingsProcessApp.main()
        }
    }
}

struct aiboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = AiboIngest.moduleName
    }

    var body: some Scene {
        MenuBarExtra(String(localized: "Aibo"), image: "HeartMenu") {
            AiboAppMenu()
        }
        .commands {
            // No `Settings` scene, so the system Settings item is gone.
            // The status-item menu does not get this equivalent: a global ⌘,
            // there would steal Settings from the frontmost app.
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) {
                    SettingsNavigator.shared.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
