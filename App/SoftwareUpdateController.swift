import AppKit
import Sparkle

/// Sparkle updater for GitHub Releases. Started once from `AppDelegate`.
@MainActor
@Observable
final class SoftwareUpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = SoftwareUpdateController()

    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    private(set) var hasUpdateFeed = false

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        hasUpdateFeed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .isEmpty == false
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
        ) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    func checkForUpdates() {
        activateForUpdateUI()
        updaterController?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    nonisolated func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String] {
        []
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            self.activateForUpdateUI()
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        for update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            self.activateForUpdateUI()
        }
    }

    /// Stay `.accessory` (no Dock). Sparkle alerts still need to become key.
    private func activateForUpdateUI() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
