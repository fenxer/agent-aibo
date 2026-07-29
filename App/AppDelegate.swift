import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PetRuntime.shared.start()
        PetPanelController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Only refresh the saved spot when restore is on; otherwise keep the last
        // user-dragged percentages for when they turn the toggle back on.
        if AppSettings.shared.restoreLastPetPosition {
            PetPanelController.shared.persistRelativePositionNow()
        }
        PetRuntime.shared.stop()
    }
}
