import AiboCore
import AiboIngest
import Foundation

@MainActor
@Observable
final class PetRuntime {
    static let shared = PetRuntime()

    private(set) var world = PetWorldState()
    private(set) var bubbleText: String?
    private(set) var cursorHooksInstalled = false
    private(set) var codexHooksInstalled = false
    private(set) var lastErrorMessage: String?

    private var server: UnixSocketServer?
    private var consumeTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    private init() {}

    func start() {
        cursorHooksInstalled = (try? CursorHooksFile.isInstalled()) ?? false
        codexHooksInstalled = (try? CodexHooksFile.isInstalled()) ?? false

        do {
            let queued = try HookQueue.drain()
            for line in queued {
                handle(jsonLine: line, at: Date())
            }

            let server = UnixSocketServer()
            let stream = try server.start()
            self.server = server

            consumeTask?.cancel()
            consumeTask = Task { [weak self] in
                for await line in stream {
                    await MainActor.run {
                        self?.handle(jsonLine: line, at: Date())
                    }
                }
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to start hook listener")
        }

        scheduleWatchdog()
    }

    func stop() {
        consumeTask?.cancel()
        idleTask?.cancel()
        watchdogTask?.cancel()
        server?.stop()
        server = nil
    }

    func installCursorHooks() {
        do {
            let command = try Self.hookCommandPath()
            try CursorHooksFile.install(command: command)
            cursorHooksInstalled = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to install Cursor hooks")
        }
    }

    func uninstallCursorHooks() {
        do {
            try CursorHooksFile.uninstall()
            cursorHooksInstalled = false
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to uninstall Cursor hooks")
        }
    }

    func installCodexHooks() {
        do {
            let command = try Self.hookCommandPath()
            try CodexHooksFile.install(command: command)
            codexHooksInstalled = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to install Codex hooks")
        }
    }

    func uninstallCodexHooks() {
        do {
            try CodexHooksFile.uninstall()
            codexHooksInstalled = false
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to uninstall Codex hooks")
        }
    }

    #if DEBUG
    /// Shows an arbitrary bubble for local UI testing. Overwritten by the next real agent event.
    func showDebugBubble(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bubbleText = trimmed
        PetPanelController.shared.refreshContent()
    }

    func clearDebugBubble() {
        bubbleText = nil
        PetPanelController.shared.refreshContent()
    }
    #endif

    private func handle(jsonLine: String, at date: Date) {
        do {
            guard let parsed = try HookLineParser.parse(jsonLine: jsonLine) else { return }
            apply(
                .agent(session: parsed.session, transition: parsed.transition, at: date)
            )
            scheduleWatchdog()
            if case .apply(.done) = parsed.transition {
                scheduleIdleDeadline()
            }
        } catch {
            // Malformed hook payloads are ignored; agents are fail-open and so are we.
        }
    }

    private func apply(_ event: PetEvent) {
        world = PetStateMachine.reduce(world, event: event)
        if let primary = world.primarySession {
            bubbleText = StatusCopy.message(for: primary.snapshot.activity, agent: primary.key.agent)
        } else {
            bubbleText = nil
        }
        PetPanelController.shared.refreshContent()
    }

    private func scheduleIdleDeadline() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            let delay = PetStateMachine.doneIdleDelay
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.apply(.idleDeadline(at: Date()))
            }
        }
    }

    private func scheduleWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            let timeout = PetStateMachine.defaultWatchdogTimeout
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.apply(.watchdog(at: Date(), timeout: timeout))
                self?.scheduleWatchdog()
            }
        }
    }

    static func hookCommandPath() throws -> String {
        let candidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/aibo-hook", isDirectory: false)
            .path
        guard FileManager.default.isExecutableFile(atPath: candidate) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return candidate
    }
}
