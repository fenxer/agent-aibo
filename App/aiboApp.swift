import AiboIngest
import SwiftUI

@main
struct aiboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = AiboIngest.moduleName
    }

    var body: some Scene {
        MenuBarExtra(String(localized: "aibo"), image: "HeartMenu") {
            AiboAppMenu()
        }

        Settings {
            SettingsView()
        }
        // contentMinSize matches normal windows / System Settings. Settings still
        // needs AppKit `.resizable` via SettingsWindowConfigurator (SO 79532884).
        .defaultSize(
            width: AppSettings.settingsWindowWidth,
            height: AppSettings.defaultSettingsWindowHeight
        )
        .windowResizability(.contentMinSize)
    }
}
