import AiboCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AiboPaths.migrateLegacyLibraryDirectoryIfNeeded()
        // Theme + language before Sparkle / UI copy.
        _ = AppSettings.shared
        SoftwareUpdateController.shared.start()
        OnboardingController.shared.startIfNeeded()
        AiboRuntime.shared.start()
        ExtensionCenter.shared.start()
        AiboPanelController.shared.show()
        PlaytimeStore.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let archives = urls.filter(Self.isBackupArchive)
        let links = urls.filter { !Self.isBackupArchive($0) }
        if let archive = archives.last {
            BackupSettingsModel.shared.importArchiveFromOutside(archive)
        }
        if !links.isEmpty {
            ExtensionLinkRouter.accept(links)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AiboRuntime.shared.refreshHostAppPresence()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
        persistAiboPositionIfNeeded()
        PlaytimeStore.shared.flushForTermination()
        AiboRuntime.shared.stop()
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
