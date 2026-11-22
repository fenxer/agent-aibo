import AppKit
import SwiftUI

/// Entry point when `aibo` is spawned with `--role=settings`.
///
/// Hosts only the Settings window and the standard menus it needs. None of the
/// desktop pet, hook socket, webhook server, Sparkle updater, or global input
/// monitors start in this process.
struct SettingsProcessApp: App {
    @NSApplicationDelegateAdaptor(SettingsProcessAppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "Close")) {
                    SettingsWindowController.shared.closeWindow()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

final class SettingsProcessAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppSettings.shared
        ExtensionCenter.shared.reloadForSettingsProcess()
        SettingsProcessClient.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        SettingsProcessClient.shared.sendOpenURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SettingsProcessClient.shared.prepareForTermination(reply: {
            sender.reply(toApplicationShouldTerminate: true)
        }) {
            return .terminateLater
        }
        return .terminateNow
    }
}
