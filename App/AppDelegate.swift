import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PetRuntime.shared.start()
        PetPanelController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PetRuntime.shared.stop()
    }
}
