import AppKit
import SwiftUI

/// Shared command list for the menu bar extra and the pet context menu.
struct AiboAppMenu: View {
    @State private var petPanelController = PetPanelController.shared
    @State private var runtime = PetRuntime.shared

    var body: some View {
        Button {
            petPanelController.toggle()
        } label: {
            Text(
                petPanelController.isVisible
                    ? String(localized: "Hide Pet")
                    : String(localized: "Show Pet")
            )
        }

        if let lastErrorMessage = runtime.lastErrorMessage {
            Divider()
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
}
