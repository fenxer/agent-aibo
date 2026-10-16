import AppKit
import ServiceManagement

/// Login-item registration for this app. macOS is the source of truth:
/// System Settings can enable or revoke it, so this is not stored in UserDefaults.
/// A fresh install is `notRegistered`, which shows as off.
@MainActor
@Observable
final class LaunchAtLoginSettings {
    static let shared = LaunchAtLoginSettings()

    private(set) var isEnabled = false
    /// Registered, but the user still has to allow it in System Settings.
    private(set) var needsApproval = false
    private(set) var updateFailed = false

    private var activationObserver: NSObjectProtocol?

    private init() {
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            needsApproval = false
        case .requiresApproval:
            isEnabled = false
            needsApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            needsApproval = false
        @unknown default:
            isEnabled = false
            needsApproval = false
        }
    }

    func setEnabled(_ wantsEnabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if wantsEnabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered, service.status != .notFound {
                try service.unregister()
            }
            updateFailed = false
        } catch {
            let code = (error as NSError).code
            let alreadyInSync = (wantsEnabled && code == kSMErrorAlreadyRegistered)
                || (!wantsEnabled && code == kSMErrorJobNotFound)
            if alreadyInSync {
                updateFailed = false
            } else if wantsEnabled, code == kSMErrorLaunchDeniedByUser {
                refresh()
                needsApproval = true
                updateFailed = false
                return
            } else {
                refresh()
                updateFailed = true
                return
            }
        }

        refresh()
        if wantsEnabled, service.status == .requiresApproval {
            needsApproval = true
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
