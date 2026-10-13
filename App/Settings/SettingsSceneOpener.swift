import SwiftUI

/// Presents the Settings scene for deep links that are not a `SettingsLink` click.
///
/// `showSettingsWindow:` no-ops on current SDKs. This view lives in the desktop
/// panel, which stays mounted while Aibo is hidden, and calls `openSettings`.
struct SettingsSceneOpener: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable private var navigator = SettingsNavigator.shared
    @State private var handledTicket = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onAppear(perform: openIfNeeded)
            .onChange(of: navigator.settingsOpenTicket) { _, _ in
                openIfNeeded()
            }
    }

    private func openIfNeeded() {
        let ticket = navigator.settingsOpenTicket
        guard ticket != handledTicket else { return }
        handledTicket = ticket
        openSettings()
        navigator.prepareForOpeningSettings()
    }
}
