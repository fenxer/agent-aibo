import AppKit
import Foundation

/// Event-driven tunnel probe (launch / wake / settings) — never a polling loop.
@MainActor
final class TunnelHealthMonitor {
    static let shared = TunnelHealthMonitor()

    enum Reason: Equatable {
        case launch
        case wake
        case settingsChanged
        case manual
    }

    private var wakeObserver: NSObjectProtocol?
    private var pendingTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleCheck(reason: .wake, allowRetry: true)
            }
        }
        scheduleCheck(reason: .launch, allowRetry: true)
    }

    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        pendingTask?.cancel()
        pendingTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    /// Coalesce rapid settings edits; wake/launch may retry once after a short delay.
    func scheduleCheck(reason: Reason, allowRetry: Bool = false) {
        pendingTask?.cancel()
        let delay: Duration = switch reason {
        case .settingsChanged: .milliseconds(400)
        case .wake: .milliseconds(800)
        case .launch, .manual: .milliseconds(0)
        }
        pendingTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.runCheck(reason: reason, allowRetry: allowRetry)
        }
    }

    private func runCheck(reason: Reason, allowRetry: Bool) async {
        let outcome = await PetRuntime.shared.checkTunnelHealth()
        guard allowRetry, outcome == .down, reason == .wake || reason == .launch else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            _ = await self?.runCheckOnce()
        }
    }

    private func runCheckOnce() async -> PetRuntime.TunnelHealthStatus {
        await PetRuntime.shared.checkTunnelHealth()
    }
}
