import AiboCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AiboPaths.migrateLegacyLibraryDirectoryIfNeeded()
        // Touch settings early so persisted theme applies before UI shows.
        _ = AppSettings.shared
        SettingsNavigator.shared.start()
        AiboRuntime.shared.start()
        AiboPanelController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Only refresh the saved spot when restore is on; otherwise keep the last
        // user-dragged percentages for when they turn the toggle back on.
        if AppSettings.shared.restoreLastAiboPosition {
            AiboPanelController.shared.persistRelativePositionNow()
        }
        AiboRuntime.shared.stop()
    }
}
