import AiboCore
import AiboIngest
import Foundation

@MainActor
@Observable
final class PetRuntime {
    static let shared = PetRuntime()

    private(set) var world = PetWorldState()
    /// Active status bubbles, newest first. Empty when idle.
    private(set) var bubbleItems: [StatusBubbleItem] = []
    private(set) var cursorHooksInstalled = false
    private(set) var codexHooksInstalled = false
    private(set) var lastErrorMessage: String?

    private var server: UnixSocketServer?
    private var consumeTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    #if DEBUG
    private var debugBubbleText: String?
    #endif

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
    /// Adds an arbitrary bubble on top of the stack for local UI testing.
    func showDebugBubble(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        debugBubbleText = trimmed
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    func clearDebugBubble() {
        debugBubbleText = nil
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }
    #endif

    private func handle(jsonLine: String, at date: Date) {
        do {
            guard let parsed = try HookLineParser.parse(jsonLine: jsonLine) else { return }
            #if DEBUG
            debugBubbleText = nil
            #endif
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
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    private func refreshBubbleItems() {
        var items: [StatusBubbleItem] = []
        for (key, snapshot) in world.sessions {
            guard snapshot.activity != .idle else { continue }
            guard let text = StatusCopy.message(
                for: snapshot.activity,
                agent: key.agent
            ) else { continue }
            items.append(
                StatusBubbleItem(
                    id: "\(key.agent.rawValue):\(key.conversationID)",
                    text: text,
                    lastEventAt: snapshot.lastEventAt
                )
            )
        }
        #if DEBUG
        if let debugBubbleText {
            items.append(
                StatusBubbleItem(
                    id: "debug",
                    text: debugBubbleText,
                    lastEventAt: Date.distantFuture
                )
            )
        }
        #endif
        bubbleItems = items.sorted { $0.lastEventAt > $1.lastEventAt }
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
