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
        // Settings defaults to `.contentSize` (fixed); `.contentMinSize` plus the
        // root view's `maxHeight: .infinity` makes the height user-resizable.
        .defaultSize(
            width: AppSettings.settingsWindowWidth,
            height: AppSettings.defaultSettingsWindowHeight
        )
        .windowResizability(.contentMinSize)
        // Prefer leading toolbar layout (Settings scene may still force
        // `.preference` — `SettingsWindowConfigurator` also asserts `.unified`).
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
