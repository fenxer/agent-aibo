import AppKit
import Sparkle

/// Sparkle updater for GitHub Releases. Started once from `AppDelegate`.
///
/// Check and Update Now both use Sparkle’s standard windows. A pending version
/// stays in About after Skip / Remind Later until the user installs it, or a
/// user-initiated check finds nothing newer.
@MainActor
@Observable
final class SoftwareUpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = SoftwareUpdateController()

    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    private(set) var hasUpdateFeed = false
    private(set) var availableUpdateDisplayVersion: String?

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private var foundUpdateThisCycle = false
    #if DEBUG
    /// Development probe: About Check / Update Now use stand-in dialogs, not Sparkle.
    private var debugPreviewActive = false
    #endif

    private enum DefaultsKey {
        static let pendingDisplayVersion = "aibo.pendingUpdateDisplayVersion"
        static let pendingVersion = "aibo.pendingUpdateVersion"
    }

    private override init() {
        super.init()
        hasUpdateFeed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .isEmpty == false
        restorePendingUpdateIfNeeded()
    }

    func start() {
        guard updaterController == nil else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        updaterController = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in
                SoftwareUpdateController.shared.canCheckForUpdates = canCheck
            }
        }
    }

    func checkForUpdates() {
        #if DEBUG
        if debugPreviewActive {
            if availableUpdateDisplayVersion != nil {
                presentDebugUpdateFound()
            } else {
                presentDebugUpToDate()
            }
            return
        }
        #endif
        activateForUpdateUI()
        updaterController?.checkForUpdates(nil)
    }

    #if DEBUG
    /// Development: stand-in “update available” dialog and About hint.
    func debugShowAvailableUpdate() {
        debugPreviewActive = true
        hasUpdateFeed = true
        availableUpdateDisplayVersion = "9.9.9"
        presentDebugUpdateFound()
    }

    /// Development: stand-in “you’re up to date” dialog.
    func debugShowUpToDate() {
        debugPreviewActive = true
        hasUpdateFeed = true
        availableUpdateDisplayVersion = nil
        presentDebugUpToDate()
    }

    /// Development: drop the fake About hint.
    func debugClearPreview() {
        debugPreviewActive = false
        hasUpdateFeed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .isEmpty == false
        availableUpdateDisplayVersion = nil
        restorePendingUpdateIfNeeded()
    }
    #endif

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    nonisolated func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundUpdateThisCycle = true
        rememberPendingUpdate(item)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        defer { foundUpdateThisCycle = false }

        // User-initiated Check includes skipped versions. No update then means
        // we're actually current. Background checks omit skipped items, so they
        // must not wipe the About hint.
        if updateCheck == .updates, !foundUpdateThisCycle {
            clearPendingUpdate()
        }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            SoftwareUpdateController.shared.activateForUpdateUI()
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            SoftwareUpdateController.shared.activateForUpdateUI()
        }
    }

    /// Stay `.accessory` (no Dock). Sparkle alerts still need to become key.
    func activateForUpdateUI() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func rememberPendingUpdate(_ item: SUAppcastItem) {
        availableUpdateDisplayVersion = item.displayVersionString
        UserDefaults.standard.set(item.displayVersionString, forKey: DefaultsKey.pendingDisplayVersion)
        UserDefaults.standard.set(item.versionString, forKey: DefaultsKey.pendingVersion)
    }

    private func clearPendingUpdate() {
        availableUpdateDisplayVersion = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingDisplayVersion)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingVersion)
    }

    private func restorePendingUpdateIfNeeded() {
        let pendingVersion = UserDefaults.standard.string(forKey: DefaultsKey.pendingVersion) ?? ""
        let pendingDisplay = UserDefaults.standard.string(forKey: DefaultsKey.pendingDisplayVersion) ?? ""
        guard !pendingVersion.isEmpty, !pendingDisplay.isEmpty else {
            availableUpdateDisplayVersion = nil
            return
        }

        let currentVersion = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? ""
        let isNewer = SUStandardVersionComparator.default.compareVersion(
            pendingVersion,
            toVersion: currentVersion
        ) == .orderedDescending
        if isNewer {
            availableUpdateDisplayVersion = pendingDisplay
        } else {
            clearPendingUpdate()
        }
    }

    #if DEBUG
    private func presentDebugUpdateFound() {
        activateForUpdateUI()
        let appName = "Aibo"
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let newer = availableUpdateDisplayVersion ?? "9.9.9"

        let alert = NSAlert()
        alert.messageText = sparkleLocalized("A new version of %@ is available!", appName)
        alert.informativeText = sparkleLocalized(
            "%@ %@ is now available—you have %@. Would you like to download it now?",
            appName,
            newer,
            current
        )
        alert.addButton(withTitle: sparkleLocalized("Install Update"))
        alert.addButton(withTitle: sparkleLocalized("Remind Me Later"))
        alert.addButton(withTitle: sparkleLocalized("Skip This Version"))
        // Install does not download. Skip / Remind Later keep the About hint.
        _ = alert.runModal()
    }

    private func presentDebugUpToDate() {
        activateForUpdateUI()
        let appName = "Aibo"
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

        let alert = NSAlert()
        alert.messageText = sparkleLocalized("You’re up to date!")
        alert.informativeText = sparkleLocalized(
            "%@ %@ is currently the newest version available.",
            appName,
            current
        )
        alert.addButton(withTitle: sparkleLocalized("OK"))
        _ = alert.runModal()
    }

    private func sparkleLocalized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle(for: SPUUpdater.self).localizedString(forKey: key, value: key, table: "Sparkle")
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
    #endif
}
