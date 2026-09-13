import AppKit
import Darwin
import IOKit

/// Sleep, lid, and screen-lock signals for playtime. Event-driven; no timers.
@MainActor
final class PlaytimePowerObserver {
    var onPauseForSleepOrLid: (() -> Void)?
    var onResumeFromSleepOrLid: (() -> Void)?
    var onScreenLockChange: ((Bool) -> Void)?

    private(set) var isLidClosed = false
    private(set) var isScreenLocked = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var clamshellPort: IONotificationPortRef?
    private var clamshellService: io_object_t = 0
    private var clamshellNotification: io_object_t = 0

    func start() {
        stop()
        isLidClosed = Self.readClamshellClosed()
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onPauseForSleepOrLid?() }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onPauseForSleepOrLid?() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isLidClosed = Self.readClamshellClosed()
                    self?.onResumeFromSleepOrLid?()
                }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isLidClosed = Self.readClamshellClosed()
                    self?.onResumeFromSleepOrLid?()
                }
            },
        ]

        let distributed = DistributedNotificationCenter.default()
        lockObservers = [
            distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isScreenLocked = true
                    self?.onScreenLockChange?(true)
                }
            },
            distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isScreenLocked = false
                    self?.onScreenLockChange?(false)
                }
            },
        ]

        startClamshellMonitor()
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
        workspaceObservers = []
        let distributed = DistributedNotificationCenter.default()
        for observer in lockObservers {
            distributed.removeObserver(observer)
        }
        lockObservers = []
        stopClamshellMonitor()
    }

    private func startClamshellMonitor() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return }
        clamshellService = service
        let port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port else {
            IOObjectRelease(service)
            clamshellService = 0
            return
        }
        clamshellPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        var notification: io_object_t = 0
        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { context, _, _, _ in
                guard let context else { return }
                let observer = Unmanaged<PlaytimePowerObserver>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    observer.handleClamshellInterest()
                }
            },
            opaque,
            &notification
        )
        if result != KERN_SUCCESS {
            stopClamshellMonitor()
            return
        }
        clamshellNotification = notification
    }

    private func handleClamshellInterest() {
        let closed = Self.readClamshellClosed()
        guard closed != isLidClosed else { return }
        isLidClosed = closed
        if closed {
            onPauseForSleepOrLid?()
        } else {
            onResumeFromSleepOrLid?()
        }
    }

    private func stopClamshellMonitor() {
        if clamshellNotification != 0 {
            IOObjectRelease(clamshellNotification)
            clamshellNotification = 0
        }
        if clamshellService != 0 {
            IOObjectRelease(clamshellService)
            clamshellService = 0
        }
        if let port = clamshellPort {
            IONotificationPortDestroy(port)
            clamshellPort = nil
        }
    }

    private static func readClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        else { return false }
        return (raw as? NSNumber)?.boolValue ?? false
    }
}
