import AiboIngest
import AppKit
import SwiftUI

@main
struct aiboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var petPanelController = PetPanelController.shared

    init() {
        // Keep the local package link exercised while ingest wiring is still a scaffold.
        _ = AiboIngest.moduleName
    }

    var body: some Scene {
        MenuBarExtra(String(localized: "aibo"), systemImage: "bird.fill") {
            Button {
                petPanelController.toggle()
            } label: {
                Text(
                    petPanelController.isVisible
                        ? String(localized: "Hide Pet")
                        : String(localized: "Show Pet")
                )
            }

            Divider()

            SettingsLink {
                Text(String(localized: "Settings…"))
            }

            Divider()

            Button(String(localized: "Quit aibo")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsView()
        }
    }
}
