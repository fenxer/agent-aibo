import AiboCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar app is not replaced when Xcode runs it again, so a second
        // pet would stay on screen. The instance that just launched keeps the
        // socket and the panel; the older ones go away.
        replaceOtherInstances()
        NSApp.setActivationPolicy(.accessory)
        AiboPaths.migrateLegacyLibraryDirectoryIfNeeded()
        // Theme + language before Sparkle / UI copy.
        _ = AppSettings.shared
        SoftwareUpdateController.shared.start()
        OnboardingController.shared.startIfNeeded()
        AiboRuntime.shared.start()
        ExtensionCenter.shared.start()
        AiboPanelController.shared.show()
        KeystrokeMonitor.shared.setEnabled(
            AppSettings.shared.keystrokeOverlayEnabled,
            promptForAccessibility: false
        )
        PlaytimeStore.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let archives = urls.filter(Self.isBackupArchive)
        let links = urls.filter { !Self.isBackupArchive($0) }
        if let archive = archives.last {
            SettingsNavigator.shared.showBackup(importArchiveURL: archive)
        }
        if !links.isEmpty {
            ExtensionLinkRouter.accept(links)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AiboRuntime.shared.refreshHostAppPresence()
        KeystrokeMonitor.shared.recheckAccessibility()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AiboLibraryStore.shared.flushPendingPersist()
        persistAiboPositionIfNeeded()
        PlaytimeStore.shared.flushForTermination()
        if AiboPanelController.shared.playQuitPortal(completion: {
            NSApp.reply(toApplicationShouldTerminate: true)
        }) {
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsProcessHost.shared.terminateForAppQuit()
        AiboLibraryStore.shared.flushPendingPersist()
        persistAiboPositionIfNeeded()
        PlaytimeStore.shared.flushForTermination()
        AiboRuntime.shared.stop()
    }

    private func replaceOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard !others.isEmpty else { return }
        for other in others {
            other.forceTerminate()
        }
        let deadline = Date().addingTimeInterval(1)
        while others.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private static func isBackupArchive(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == AiboBackupArchive.fileExtension
    }

    private func persistAiboPositionIfNeeded() {
        // Only refresh the saved spot when restore is on; otherwise keep the last
        // user-dragged percentages for when they turn the toggle back on.
        guard AppSettings.shared.restoreLastAiboPosition else { return }
        OnboardingController.shared.restorePositionIfNeeded()
        AiboPanelController.shared.persistRelativePositionNow()
    }
}
