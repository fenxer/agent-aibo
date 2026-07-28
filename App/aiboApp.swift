import AiboIngest
import SwiftUI

@main
struct aiboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = AiboIngest.moduleName
    }

    var body: some Scene {
        MenuBarExtra(String(localized: "aibo"), systemImage: "bird.fill") {
            AiboAppMenu()
        }

        Settings {
            SettingsView()
        }
    }
}
