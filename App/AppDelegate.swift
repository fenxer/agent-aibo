import AiboCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AiboPaths.migrateLegacyLibraryDirectoryIfNeeded()
        // Theme + language before Sparkle / UI copy.
        _ = AppSettings.shared
        SoftwareUpdateController.shared.start()
        SettingsNavigator.shared.start()
        OnboardingController.shared.startIfNeeded()
        AiboRuntime.shared.start()
        AiboPanelController.shared.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AiboRuntime.shared.refreshHostAppPresence()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        persistAiboPositionIfNeeded()
        if AiboPanelController.shared.playQuitPortal(completion: {
            NSApp.reply(toApplicationShouldTerminate: true)
        }) {
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistAiboPositionIfNeeded()
        AiboRuntime.shared.stop()
    }

    private func persistAiboPositionIfNeeded() {
        // Only refresh the saved spot when restore is on; otherwise keep the last
        // user-dragged percentages for when they turn the toggle back on.
        guard AppSettings.shared.restoreLastAiboPosition else { return }
        OnboardingController.shared.restorePositionIfNeeded()
        AiboPanelController.shared.persistRelativePositionNow()
    }
}
