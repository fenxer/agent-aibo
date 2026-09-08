import AppKit
import Sparkle

/// Sparkle updater for GitHub Releases. Started once from `AppDelegate`.
///
/// Scheduled / Check probes never present Sparkle’s “update available” alert.
/// A pending version stays in About until the user installs it. Update Now
/// starts a real update session and installs without that confirmation alert.
@MainActor
@Observable
final class SoftwareUpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = SoftwareUpdateController()

    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    private(set) var hasUpdateFeed = false
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var availableUpdateDisplayVersion: String?

    private var updater: SPUUpdater?
    private var userDriver: SoftwareUpdateUserDriver?
    private var canCheckObservation: NSKeyValueObservation?
    private var installRequested = false

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
        guard updater == nil else { return }

        let driver = SoftwareUpdateUserDriver(hostBundle: .main, controller: self)
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: self
        )
        do {
            try updater.start()
        } catch {
            return
        }
        userDriver = driver
        self.updater = updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        canCheckObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in
                SoftwareUpdateController.shared.canCheckForUpdates = canCheck
            }
        }
    }

    /// Probe the appcast and refresh the About row. No Sparkle windows.
    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        isChecking = true
        updater.checkForUpdateInformation()
    }

    /// User chose Update Now: download, install, and relaunch.
    func installAvailableUpdate() {
        guard let updater, updater.canCheckForUpdates else { return }
        installRequested = true
        isInstalling = true
        isChecking = true
        activateForUpdateUI()
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        updater?.automaticallyChecksForUpdates = enabled
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    nonisolated func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        rememberPendingUpdate(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        clearPendingUpdate()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        isChecking = false
        if error != nil {
            installRequested = false
            isInstalling = false
        }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            SoftwareUpdateController.shared.activateForUpdateUI()
        }
    }

    /// Stay `.accessory` (no Dock). Sparkle progress windows still need to become key.
    func activateForUpdateUI() {
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate var shouldInstallFoundUpdate: Bool {
        installRequested
    }

    fileprivate func rememberPendingUpdate(_ item: SUAppcastItem) {
        availableUpdateDisplayVersion = item.displayVersionString
        UserDefaults.standard.set(item.displayVersionString, forKey: DefaultsKey.pendingDisplayVersion)
        UserDefaults.standard.set(item.versionString, forKey: DefaultsKey.pendingVersion)
    }

    fileprivate func finishInstallSession() {
        installRequested = false
        isInstalling = false
        isChecking = false
    }

    private func clearPendingUpdate() {
        availableUpdateDisplayVersion = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingDisplayVersion)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingVersion)
    }

    private func restorePendingUpdateIfNeeded() {
        let pendingVersion = UserDefaults.standard.string(forKey: DefaultsKey.pendingVersion) ?? ""
        let pendingDisplay = UserDefaults.standard.string(forKey: DefaultsKey.pendingDisplayVersion) ?? ""
        guard !pendingVersion.isEmpty, !pendingDisplay.isEmpty else { return }

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
}

/// Forwards download/install chrome to Sparkle’s standard driver, but never
/// presents the “update available” / “you’re up to date” alerts.
@MainActor
private final class SoftwareUpdateUserDriver: NSObject, SPUUserDriver {
    private let standard: SPUStandardUserDriver
    private weak var controller: SoftwareUpdateController?

    init(hostBundle: Bundle, controller: SoftwareUpdateController) {
        self.standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: controller)
        self.controller = controller
        super.init()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void
    ) {
        let checks = controller?.automaticallyChecksForUpdates ?? false
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: checks, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // About already shows Checking… / Update Now. Skip Sparkle’s check window.
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
    ) {
        controller?.rememberPendingUpdate(appcastItem)
        if controller?.shouldInstallFoundUpdate == true {
            controller?.activateForUpdateUI()
            reply(.install)
        } else {
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if controller?.shouldInstallFoundUpdate == true {
            standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
        } else {
            acknowledgement()
        }
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        controller?.activateForUpdateUI()
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        controller?.activateForUpdateUI()
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void) {
        controller?.activateForUpdateUI()
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        standard.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
        controller?.finishInstallSession()
    }

    func showUpdateInFocus() {
        controller?.activateForUpdateUI()
        standard.showUpdateInFocus()
    }
}
