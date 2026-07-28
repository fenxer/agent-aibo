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
    private(set) var webhookListening = false
    private(set) var lastErrorMessage: String?
    /// Newest-first webhook receive history shown in Settings (capped).
    private(set) var receiveLogEntries: [ReceiveLogEntry] = []
    /// Total records currently on disk (may exceed the UI window).
    private(set) var receiveLogTotalCount = 0

    private var server: UnixSocketServer?
    private var webhookServer: WebhookServer?
    private var consumeTask: Task<Void, Never>?
    private var webhookTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var webhookBubbles: [StatusBubbleItem] = []
    private var webhookExpiryTasks: [String: Task<Void, Never>] = [:]
    /// Project / model labels keyed by session; merged across hook events.
    private var sessionDisplayMeta: [SessionKey: SessionDisplayMeta] = [:]
    #if DEBUG
    private var debugBubbleItem: StatusBubbleItem?
    #endif

    private static let webhookBubbleTTL: TimeInterval = 12

    private struct SessionDisplayMeta: Equatable, Sendable {
        var projectName: String?
        var modelName: String?
    }

    private init() {}

    func start() {
        cursorHooksInstalled = (try? CursorHooksFile.isInstalled()) ?? false
        codexHooksInstalled = (try? CodexHooksFile.isInstalled()) ?? false
        reloadReceiveLog()

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

        syncWebhookServer()
        scheduleWatchdog()
    }

    func stop() {
        consumeTask?.cancel()
        webhookTask?.cancel()
        idleTask?.cancel()
        watchdogTask?.cancel()
        for task in webhookExpiryTasks.values {
            task.cancel()
        }
        webhookExpiryTasks.removeAll()
        server?.stop()
        server = nil
        webhookServer?.stop()
        webhookServer = nil
        webhookListening = false
    }

    func syncWebhookServer() {
        webhookTask?.cancel()
        webhookTask = nil
        webhookServer?.stop()
        webhookServer = nil
        webhookListening = false

        guard AppSettings.shared.webhookEnabled else { return }

        let port = AppSettings.shared.webhookPort
        let secretBox = WebhookSecretBox(secret: AppSettings.shared.webhookSecret)
        let server = WebhookServer(port: port, secretProvider: {
            secretBox.secret
        })

        do {
            let stream = try server.start()
            webhookServer = server
            webhookListening = true
            lastErrorMessage = nil

            webhookTask = Task { [weak self] in
                for await delivery in stream {
                    await MainActor.run {
                        self?.ingestWebhook(delivery)
                    }
                }
                await MainActor.run {
                    self?.webhookListening = false
                }
            }
        } catch {
            webhookServer = nil
            webhookListening = false
            lastErrorMessage = String(localized: "Failed to start webhook listener")
        }
    }

    func ingestWebhook(_ delivery: WebhookDelivery) {
        let item = StatusBubbleItem(
            id: "webhook:\(delivery.id)",
            text: delivery.displayText,
            lastEventAt: delivery.receivedAt,
            agentName: delivery.source
        )
        webhookBubbles.removeAll { $0.id == item.id }
        webhookBubbles.append(item)
        recordReceive(delivery)
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
        scheduleWebhookExpiry(for: item.id)
    }

    /// Local test / DEBUG helper: format raw body the same way as HTTP ingest.
    func ingestWebhookBody(_ body: Data, id: String = UUID().uuidString) {
        let parsed = WebhookMessageFormatter.parse(from: body)
        ingestWebhook(
            WebhookDelivery(
                id: id,
                source: parsed.source,
                displayText: parsed.displayText,
                receivedAt: Date()
            )
        )
    }

    /// Clears a dismissible bubble (currently `.failed` agent status) on user click.
    func dismissBubble(id: String) {
        for (key, snapshot) in world.sessions {
            guard snapshot.activity == .failed else { continue }
            let itemID = "\(key.agent.rawValue):\(key.conversationID)"
            guard itemID == id else { continue }
            apply(.agent(session: key, transition: .apply(.idle), at: Date()))
            return
        }
    }

    func clearReceiveLog() {
        do {
            try ReceiveLogStore.clear()
            receiveLogEntries = []
            receiveLogTotalCount = 0
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to clear receive log")
        }
    }

    func exportReceiveLog() -> Data? {
        do {
            return try ReceiveLogStore.exportJSON()
        } catch {
            lastErrorMessage = String(localized: "Failed to export receive log")
            return nil
        }
    }

    private func recordReceive(_ delivery: WebhookDelivery) {
        let entry = ReceiveLogEntry(
            receivedAt: delivery.receivedAt,
            source: delivery.source,
            message: delivery.displayText,
            deliveryID: delivery.id
        )
        do {
            try ReceiveLogStore.append(entry)
            receiveLogEntries.insert(entry, at: 0)
            if receiveLogEntries.count > ReceiveLogStore.uiDisplayLimit {
                receiveLogEntries = Array(receiveLogEntries.prefix(ReceiveLogStore.uiDisplayLimit))
            }
            receiveLogTotalCount = (try? ReceiveLogStore.count()) ?? receiveLogEntries.count
        } catch {
            lastErrorMessage = String(localized: "Failed to write receive log")
        }
    }

    private func reloadReceiveLog() {
        receiveLogEntries = (try? ReceiveLogStore.load(limit: ReceiveLogStore.uiDisplayLimit)) ?? []
        receiveLogTotalCount = (try? ReceiveLogStore.count()) ?? receiveLogEntries.count
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
    func showDebugBubble(
        text: String,
        agentName: String = "Cursor",
        projectName: String? = nil,
        modelName: String? = nil,
        showCursorIcon: Bool = true
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let trimmedAgent = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProject = projectName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        debugBubbleItem = StatusBubbleItem(
            id: "debug",
            text: trimmedText,
            lastEventAt: Date.distantFuture,
            agentName: trimmedAgent.isEmpty ? "Debug" : trimmedAgent,
            iconAssetName: showCursorIcon ? "cursor" : nil,
            projectName: (trimmedProject?.isEmpty == false) ? trimmedProject : nil,
            modelName: (trimmedModel?.isEmpty == false) ? trimmedModel : nil
        )
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    func clearDebugBubble() {
        debugBubbleItem = nil
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    /// Posts a signed webhook to the local listener (requires webhook enabled).
    func postTestWebhook(body: Data) async -> String? {
        guard AppSettings.shared.webhookEnabled else {
            return String(localized: "Enable the webhook listener in Integrations first.")
        }
        let secret = AppSettings.shared.webhookSecret
        let urlString = AppSettings.shared.webhookURLString
        guard let url = URL(string: urlString) else {
            return String(localized: "Invalid webhook URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(WebhookSignature.sign(body: body, secret: secret), forHTTPHeaderField: "X-Webhook-Signature")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Webhook-ID")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200..<300).contains(code) { return nil }
            return String(localized: "Webhook test failed (\(code))")
        } catch {
            return String(localized: "Webhook test request failed")
        }
    }
    #endif

    private func handle(jsonLine: String, at date: Date) {
        do {
            guard let parsed = try HookLineParser.parse(jsonLine: jsonLine) else { return }
            #if DEBUG
            debugBubbleItem = nil
            #endif
            mergeDisplayMeta(
                for: parsed.session,
                projectName: parsed.projectName,
                modelName: parsed.modelName
            )
            if case .removeSession = parsed.transition {
                sessionDisplayMeta.removeValue(forKey: parsed.session)
            }
            apply(
                .agent(session: parsed.session, transition: parsed.transition, at: date)
            )
            scheduleWatchdog()
            if case let .apply(activity) = parsed.transition,
               PetStateMachine.schedulesIdleFallback(activity)
            {
                scheduleIdleDeadline()
            }
        } catch {
            // Malformed hook payloads are ignored; agents are fail-open and so are we.
        }
    }

    private func mergeDisplayMeta(
        for session: SessionKey,
        projectName: String?,
        modelName: String?
    ) {
        guard projectName != nil || modelName != nil else { return }
        var meta = sessionDisplayMeta[session] ?? SessionDisplayMeta()
        if let projectName { meta.projectName = projectName }
        if let modelName { meta.modelName = modelName }
        sessionDisplayMeta[session] = meta
    }

    private func apply(_ event: PetEvent) {
        world = PetStateMachine.reduce(world, event: event)
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    private func refreshBubbleItems() {
        var items: [StatusBubbleItem] = []
        for (key, snapshot) in world.sessions {
            if snapshot.activity == .idle {
                sessionDisplayMeta.removeValue(forKey: key)
                continue
            }
            guard let text = StatusCopy.statusPhrase(for: snapshot.activity) else { continue }
            let meta = sessionDisplayMeta[key]
            items.append(
                StatusBubbleItem(
                    id: "\(key.agent.rawValue):\(key.conversationID)",
                    text: text,
                    lastEventAt: snapshot.lastEventAt,
                    isDismissible: snapshot.activity == .failed,
                    agentName: StatusCopy.displayName(key.agent),
                    iconAssetName: Self.iconAssetName(for: key.agent),
                    projectName: meta?.projectName,
                    modelName: meta?.modelName
                )
            )
        }
        items.append(contentsOf: webhookBubbles)
        #if DEBUG
        if let debugBubbleItem {
            items.append(debugBubbleItem)
        }
        #endif
        bubbleItems = items.sorted { $0.lastEventAt > $1.lastEventAt }
    }

    private static func iconAssetName(for agent: AgentKind) -> String? {
        switch agent {
        case .cursor: "cursor"
        case .codex: nil
        }
    }

    private func scheduleWebhookExpiry(for id: String) {
        webhookExpiryTasks[id]?.cancel()
        webhookExpiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.webhookBubbleTTL))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.webhookBubbles.removeAll { $0.id == id }
                self.webhookExpiryTasks[id] = nil
                self.refreshBubbleItems()
                PetPanelController.shared.refreshContent()
            }
        }
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

/// Thread-safe secret snapshot for the webhook accept queue.
private final class WebhookSecretBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String

    init(secret: String) {
        value = secret
    }

    var secret: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
