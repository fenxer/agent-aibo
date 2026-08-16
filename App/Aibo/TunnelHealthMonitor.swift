import AppKit
import Foundation
import Network

/// Event-driven tunnel probe — path changes + wake/launch/settings/manual; never a polling loop.
@MainActor
final class TunnelHealthMonitor {
    static let shared = TunnelHealthMonitor()

    enum Reason: Equatable {
        case launch
        case wake
        /// Local network became usable (unsatisfied → satisfied, or interface set changed while up).
        case pathBecameSatisfied
        /// Local network dropped — mark down without HTTP (Warning present is deferred).
        case pathBecameUnsatisfied
        case settingsChanged
        case manual
    }

    /// Cumulative offsets from series start (network-ready). Stops early on confirmed recovery.
    private static let recoveryProbeOffsets: [Duration] = [
        .seconds(0),
        .seconds(3),
        .seconds(10),
        .seconds(30),
        .seconds(60),
    ]
    private static let pathDebounce: Duration = .milliseconds(1_500)
    private static let wakeDebounce: Duration = .seconds(2)
    private static let settingsDebounce: Duration = .milliseconds(400)

    private var wakeObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var lastInterfaceFingerprint: String?
    private var pathDebounceTask: Task<Void, Never>?
    private var seriesTask: Task<Void, Never>?
    private var oneShotTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.aibo.tunnel-path", qos: .utility))

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleCheck(reason: .wake)
            }
        }

        scheduleCheck(reason: .launch)
    }

    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        pathMonitor?.cancel()
        pathMonitor = nil
        lastPathStatus = nil
        lastInterfaceFingerprint = nil
        pathDebounceTask?.cancel()
        pathDebounceTask = nil
        cancelProbeWork()
    }

    /// Coalesce rapid settings edits; path/wake/launch run a bounded recovery series.
    func scheduleCheck(reason: Reason) {
        switch reason {
        case .pathBecameUnsatisfied:
            cancelProbeWork()
            AiboRuntime.shared.markTunnelOfflineFromLocalPath()

        case .launch, .wake, .pathBecameSatisfied:
            let delay: Duration = switch reason {
            case .wake: Self.wakeDebounce
            case .pathBecameSatisfied: .zero // already debounced in handlePathUpdate
            case .launch: .zero
            default: .zero
            }
            startRecoverySeries(initialDelay: delay)

        case .settingsChanged, .manual:
            scheduleOneShot(
                delay: reason == .settingsChanged ? Self.settingsDebounce : .zero,
                clearPolicy: .immediate
            )
        }
    }

    // MARK: - Path

    private func handlePathUpdate(_ path: NWPath) {
        pathDebounceTask?.cancel()
        let status = path.status
        let fingerprint = Self.interfaceFingerprint(path)
        pathDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pathDebounce)
            guard !Task.isCancelled else { return }
            self?.applyDebouncedPath(status: status, fingerprint: fingerprint)
        }
    }

    private func applyDebouncedPath(status: NWPath.Status, fingerprint: String) {
        let previousStatus = lastPathStatus
        let previousFingerprint = lastInterfaceFingerprint
        lastPathStatus = status
        lastInterfaceFingerprint = fingerprint

        // First callback: baseline only — launch series already covers cold start.
        guard let previousStatus else { return }

        let isUp = status == .satisfied
        let wasUp = previousStatus == .satisfied

        if !isUp {
            if wasUp {
                scheduleCheck(reason: .pathBecameUnsatisfied)
            }
            return
        }

        let becameSatisfied = !wasUp
        let interfacesChanged = fingerprint != previousFingerprint
        if becameSatisfied || interfacesChanged {
            scheduleCheck(reason: .pathBecameSatisfied)
        }
    }

    private static func interfaceFingerprint(_ path: NWPath) -> String {
        path.availableInterfaces
            .map { "\($0.name):\($0.type)" }
            .sorted()
            .joined(separator: "|")
    }

    // MARK: - Probe scheduling

    private func cancelProbeWork() {
        seriesTask?.cancel()
        seriesTask = nil
        oneShotTask?.cancel()
        oneShotTask = nil
    }

    private func startRecoverySeries(initialDelay: Duration) {
        cancelProbeWork()
        seriesTask = Task { [weak self] in
            if initialDelay > .zero {
                try? await Task.sleep(for: initialDelay)
            }
            guard let self, !Task.isCancelled else { return }

            // Local path still down — don't burn HTTP probes.
            if let status = self.lastPathStatus, status != .satisfied {
                AiboRuntime.shared.markTunnelOfflineFromLocalPath()
                return
            }

            let clock = ContinuousClock.now
            for offset in Self.recoveryProbeOffsets {
                let elapsed = ContinuousClock.now - clock
                let remaining = offset - elapsed
                if remaining > .zero {
                    try? await Task.sleep(for: remaining)
                }
                guard !Task.isCancelled else { return }

                if let status = self.lastPathStatus, status != .satisfied {
                    AiboRuntime.shared.markTunnelOfflineFromLocalPath()
                    return
                }

                let outcome = await AiboRuntime.shared.checkTunnelHealth(clearPolicy: .recovery)
                guard !Task.isCancelled else { return }

                switch outcome {
                case .ok:
                    // Confirmed recovery (bubble cleared after 2× OK) — stop early.
                    if !AiboRuntime.shared.tunnelWarningBubbleVisible {
                        return
                    }
                case .skipped:
                    return
                case .down, .listenerStopped, .unknown, .checking:
                    continue
                }
            }
        }
    }

    private func scheduleOneShot(delay: Duration, clearPolicy: AiboRuntime.TunnelHealthClearPolicy) {
        cancelProbeWork()
        oneShotTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard self != nil, !Task.isCancelled else { return }
            _ = await AiboRuntime.shared.checkTunnelHealth(clearPolicy: clearPolicy)
        }
    }
}
