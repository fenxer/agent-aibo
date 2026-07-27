import AiboIngest
import AppKit
import SwiftUI

@main
struct aiboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var petPanelController = PetPanelController.shared
    @State private var runtime = PetRuntime.shared

    init() {
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

            if runtime.cursorHooksInstalled {
                Button(String(localized: "Uninstall Cursor Hooks")) {
                    runtime.uninstallCursorHooks()
                }
            } else {
                Button(String(localized: "Install Cursor Hooks")) {
                    runtime.installCursorHooks()
                }
            }

            if let lastErrorMessage = runtime.lastErrorMessage {
                Text(lastErrorMessage)
                    .foregroundStyle(.secondary)
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
