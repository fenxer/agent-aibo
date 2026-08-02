import AiboCore
import AiboIngest
import Foundation
import SwiftUI

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
    /// Last tunnel probe result for Integrations (Unknown / OK / Down / …).
    private(set) var tunnelHealthStatus: TunnelHealthStatus = .unknown
    /// Newest-first webhook receive history shown in Settings (capped).
    private(set) var receiveLogEntries: [ReceiveLogEntry] = []
    /// Total records currently on disk (may exceed the UI window).
    private(set) var receiveLogTotalCount = 0

    enum TunnelHealthStatus: Equatable, Sendable {
        case unknown
        /// Webhook disabled or Public URL empty — probe skipped.
        case skipped
        case ok
        case down
        /// Public URL set but local listener is not running.
        case listenerStopped

        var settingsLabel: String {
            switch self {
            case .unknown: String(localized: "Unknown")
            case .skipped: String(localized: "—")
            case .ok: String(localized: "OK")
            case .down: String(localized: "Down")
            case .listenerStopped: String(localized: "Listener stopped")
            }
        }
    }

    private static let tunnelWarningBubbleID = "tunnel:health"
    private static let tunnelProbeTimeout: TimeInterval = 10
    /// First time we detected tunnel down; kept across reprobes so relative time doesn't jump.
    private var tunnelWarningDetectedAt: Date?

    private var server: UnixSocketServer?
    private var webhookServer: WebhookServer?
    private var consumeTask: Task<Void, Never>?
    private var webhookTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    /// One-shot refresh when Cursor `.usingTool` has been silent long enough for the stall CTA.
    private var cursorUsingToolStallTasks: [SessionKey: Task<Void, Never>] = [:]
    private var webhookBubbles: [StatusBubbleItem] = []
    /// Separate from webhookBubbles so dismiss mode / Receive Log never touch it.
    private var tunnelWarningBubble: StatusBubbleItem?
    private var webhookExpiryTasks: [String: Task<Void, Never>] = [:]
    private var tunnelProbeTask: Task<Void, Never>?
    /// Project / model labels keyed by session; merged across hook events.
    private var sessionDisplayMeta: [SessionKey: SessionDisplayMeta] = [:]
    /// Last hook event name per session — drives Petdex sprite row lookup.
    private var sessionHookEvents: [SessionKey: String] = [:]
    #if DEBUG
    private var debugBubbleItems: [StatusBubbleItem] = []
    /// When true, every hook line (queue drain + live socket) is appended to ingest-log.jsonl.
    private(set) var ingestLoggingEnabled: Bool
    private(set) var ingestLogEntryCount = 0
    private static let ingestLoggingDefaultsKey = "debug.ingestLoggingEnabled"
    #endif

    /// Sprite row for the primary session (idle when none).
    var primarySpriteState: PetdexSpriteState {
        guard let primary = world.primarySession else { return .idle }
        return HookSpriteSettings.shared.resolve(
            agent: primary.key.agent,
            hookEventName: sessionHookEvents[primary.key],
            activity: primary.snapshot.activity
        )
    }
    private struct SessionDisplayMeta: Equatable, Sendable {
        var projectName: String?
        var modelName: String?
        var isSubagent: Bool = false
    }

    private enum HookIngestSource: String {
        case queue
        case socket
    }

    private init() {
        #if DEBUG
        if UserDefaults.standard.object(forKey: Self.ingestLoggingDefaultsKey) != nil {
            ingestLoggingEnabled = UserDefaults.standard.bool(forKey: Self.ingestLoggingDefaultsKey)
        } else {
            // Default on in DEBUG so cold-start ghosts are catchable without opening Settings first.
            ingestLoggingEnabled = true
        }
        ingestLogEntryCount = (try? IngestLogStore.count()) ?? 0
        #endif
    }

    func start() {
        cursorHooksInstalled = (try? CursorHooksFile.isInstalled()) ?? false
        codexHooksInstalled = (try? CodexHooksFile.isInstalled()) ?? false
        reloadReceiveLog()

        do {
            let queued = try HookQueue.drain()
            #if DEBUG
            recordIngestDrain(count: queued.count)
            #endif
            let drainedAt = Date()
            for item in queued {
                handle(
                    jsonLine: item.line,
                    at: drainedAt,
                    source: .queue,
                    queuedAt: item.queuedAt
                )
            }

            let server = UnixSocketServer()
            let stream = try server.start()
            self.server = server

            consumeTask?.cancel()
            consumeTask = Task { [weak self] in
                for await line in stream {
                    await MainActor.run {
                        self?.handle(
                            jsonLine: line,
                            at: Date(),
                            source: .socket,
                            queuedAt: nil
                        )
                    }
                }
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to start hook listener")
        }

        syncWebhookServer()
        syncMusicPlaybackMonitor()
        scheduleWatchdog()
        TunnelHealthMonitor.shared.start()
    }

    func stop() {
        TunnelHealthMonitor.shared.stop()
        consumeTask?.cancel()
        webhookTask?.cancel()
        idleTask?.cancel()
        watchdogTask?.cancel()
        tunnelProbeTask?.cancel()
        tunnelProbeTask = nil
        for task in cursorUsingToolStallTasks.values {
            task.cancel()
        }
        cursorUsingToolStallTasks.removeAll()
        for task in webhookExpiryTasks.values {
            task.cancel()
        }
        webhookExpiryTasks.removeAll()
        server?.stop()
        server = nil
        webhookServer?.stop()
        webhookServer = nil
        webhookListening = false
        MusicPlaybackMonitor.shared.stop()
    }

    func syncMusicPlaybackMonitor() {
        if AppSettings.shared.musicNotesEnabled {
            MusicPlaybackMonitor.shared.start()
        } else {
            MusicPlaybackMonitor.shared.stop()
        }
    }

    func syncWebhookServer() {
        webhookTask?.cancel()
        webhookTask = nil
        webhookServer?.stop()
        webhookServer = nil
        webhookListening = false

        guard AppSettings.shared.webhookEnabled else { return }

        let port = AppSettings.shared.webhookPort
        // Snapshot for the accept queue; regenerate restarts the server via syncWebhookServer().
        let secret = AppSettings.shared.webhookSecret
        let server = WebhookServer(port: port, secretProvider: { secret })

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
        TunnelHealthMonitor.shared.scheduleCheck(reason: .settingsChanged)
    }

    /// Probe the configured public URL once. GET: 405 from our listener means the tunnel reached this Mac.
    @discardableResult
    func checkTunnelHealth() async -> TunnelHealthStatus {
        tunnelProbeTask?.cancel()

        guard AppSettings.shared.webhookEnabled else {
            applyTunnelHealth(.skipped)
            return .skipped
        }
        guard AppSettings.shared.resolvedPublicWebhookURL != nil else {
            applyTunnelHealth(.skipped)
            return .skipped
        }
        guard webhookListening else {
            applyTunnelHealth(.listenerStopped)
            return .listenerStopped
        }

        let status: TunnelHealthStatus
        let probe = Task { await Self.probePublicWebhookURL() }
        tunnelProbeTask = Task { _ = await probe.value }
        status = await probe.value
        guard !Task.isCancelled else { return tunnelHealthStatus }
        applyTunnelHealth(status)
        return status
    }

    private func applyTunnelHealth(_ status: TunnelHealthStatus) {
        tunnelHealthStatus = status
        switch status {
        case .down:
            presentTunnelWarningBubble()
        case .ok, .skipped:
            // Recovered or health-check disabled — drop warning and reset the clock.
            clearTunnelWarningBubble(resetDetectionClock: true)
        case .unknown, .listenerStopped:
            // Transient listener restarts must not clear/recreate the warning
            // (that was resetting lastEventAt and making “40s” jump to “18s”).
            break
        }
    }

    private func presentTunnelWarningBubble() {
        let detectedAt = tunnelWarningDetectedAt ?? Date()
        tunnelWarningDetectedAt = detectedAt
        let item = StatusBubbleItem(
            id: Self.tunnelWarningBubbleID,
            text: String(localized: "Tunnel is down, take a look!"),
            lastEventAt: detectedAt,
            kind: .warning,
            isDismissible: true,
            animatesEllipsis: false
        )
        if tunnelWarningBubble != item {
            tunnelWarningBubble = item
            refreshBubbleItems()
            PetPanelController.shared.refreshContent()
        }
    }

    private func clearTunnelWarningBubble(resetDetectionClock: Bool = false) {
        if resetDetectionClock {
            tunnelWarningDetectedAt = nil
        }
        guard tunnelWarningBubble != nil else { return }
        tunnelWarningBubble = nil
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    private static func probePublicWebhookURL() async -> TunnelHealthStatus {
        guard let url = AppSettings.shared.resolvedPublicWebhookURL else {
            return .skipped
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = tunnelProbeTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // Origin reached (our listener answers 405 to GET). Gateway/tunnel failures are 5xx.
            if code >= 500 || code < 0 {
                return .down
            }
            return .ok
        } catch {
            return .down
        }
    }

    func ingestWebhook(_ delivery: WebhookDelivery) {
        let trimmedSummary = delivery.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStatus = delivery.status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryText =
            if let trimmedSummary, !trimmedSummary.isEmpty {
                trimmedSummary
            } else {
                delivery.displayText
            }
        let dismissMode = AppSettings.shared.webhookDismissMode
        let item = StatusBubbleItem(
            id: "webhook:\(delivery.id)",
            text: summaryText,
            lastEventAt: delivery.receivedAt,
            kind: .webhook,
            isDismissible: dismissMode == .onClick,
            animatesEllipsis: false,
            agentName: delivery.source,
            statusLabel: (trimmedStatus?.isEmpty == false) ? trimmedStatus : nil
        )
        webhookBubbles.removeAll { $0.id == item.id }
        webhookBubbles.append(item)
        if !delivery.skipReceiveLog {
            recordReceive(delivery)
        }
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
        switch dismissMode {
        case .onClick:
            cancelWebhookExpiry(for: item.id)
        case .afterSeconds:
            scheduleWebhookExpiry(
                for: item.id,
                seconds: AppSettings.shared.webhookAutoDismissSeconds
            )
        }
    }

    /// Local test / DEBUG helper: format raw body the same way as HTTP ingest.
    /// Skips Receive Log — Development probes must not pollute real inbound history.
    func ingestWebhookBody(_ body: Data, id: String = UUID().uuidString) {
        let parsed = WebhookMessageFormatter.parse(from: body)
        ingestWebhook(
            WebhookDelivery(
                id: id,
                source: parsed.source,
                status: parsed.status,
                summary: parsed.summary,
                displayText: parsed.displayText,
                receivedAt: Date(),
                skipReceiveLog: true
            )
        )
    }

    /// Clears a dismissible bubble on user click (webhook, tunnel warning, or `.failed` agent status).
    func dismissBubble(id: String) {
        if tunnelWarningBubble?.id == id {
            // User dismissed — keep detection clock so a later re-show stays stable
            // until the tunnel actually recovers.
            clearTunnelWarningBubble(resetDetectionClock: false)
            return
        }
        if webhookBubbles.contains(where: { $0.id == id && $0.isDismissible }) {
            removeWebhookBubble(id: id)
            return
        }
        for (key, snapshot) in world.sessions {
            guard snapshot.activity == .failed else { continue }
            let itemID = "\(key.agent.rawValue):\(key.conversationID)"
            guard itemID == id else { continue }
            apply(.agent(session: key, transition: .apply(.idle), at: Date()))
            return
        }
    }

    #if DEBUG
    /// Stacks the tunnel Warning bubble for Bubble Preview (no probe).
    func showDebugTunnelWarningBubble() {
        let detectedAt = tunnelWarningDetectedAt ?? Date()
        tunnelWarningDetectedAt = detectedAt
        tunnelWarningBubble = StatusBubbleItem(
            id: Self.tunnelWarningBubbleID,
            text: String(localized: "Tunnel is down, take a look!"),
            lastEventAt: detectedAt,
            kind: .warning,
            isDismissible: true,
            animatesEllipsis: false
        )
        tunnelHealthStatus = .down
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }
    #endif

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
    /// Adds an arbitrary bubble for local UI testing.
    ///
    /// - Parameter stack: When true, appends; when false, replaces any existing debug bubbles.
    /// - Parameter isAwaitingApproval: Renders the approval CTA row (arrow + localized prompt).
    func showDebugBubble(
        text: String,
        agentName: String = "Cursor",
        projectName: String? = nil,
        modelName: String? = nil,
        showCursorIcon: Bool = true,
        isSubagent: Bool = false,
        stack: Bool = false,
        isAwaitingApproval: Bool = false
    ) {
        let trimmedAgent = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayAgent = isSubagent
            ? "Subagent"
            : (trimmedAgent.isEmpty ? "Debug" : trimmedAgent)
        let agentKind = Self.debugAgentKind(from: trimmedAgent)
        let trimmedText: String
        if isAwaitingApproval {
            trimmedText = StatusCopy.statusPhrase(for: .waiting) ?? "needs your approval"
        } else {
            trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }
        }
        let trimmedProject = projectName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let iconAssetName: String? = {
            if isAwaitingApproval {
                return Self.iconAssetName(for: agentKind)
            }
            return showCursorIcon ? "cursor" : nil
        }()
        if !stack {
            debugBubbleItems = []
        }
        let item = StatusBubbleItem(
            id: "debug-\(UUID().uuidString)",
            text: trimmedText,
            lastEventAt: Date.distantFuture.addingTimeInterval(TimeInterval(debugBubbleItems.count)),
            animatesEllipsis: !isAwaitingApproval,
            isAwaitingApproval: isAwaitingApproval,
            agentName: displayAgent,
            iconAssetName: iconAssetName,
            projectName: (trimmedProject?.isEmpty == false) ? trimmedProject : nil,
            modelName: (trimmedModel?.isEmpty == false) ? trimmedModel : nil,
            isSubagent: isSubagent && !isAwaitingApproval,
            agent: isAwaitingApproval ? agentKind : nil
        )
        debugBubbleItems.append(item)
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    func clearDebugBubble() {
        debugBubbleItems = []
        clearTunnelWarningBubble(resetDetectionClock: true)
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    private static func debugAgentKind(from agentName: String) -> AgentKind {
        agentName.localizedCaseInsensitiveContains("codex") ? .codex : .cursor
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
        request.setValue("1", forHTTPHeaderField: WebhookRequestHandler.testHeaderName)
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

    func setIngestLoggingEnabled(_ enabled: Bool) {
        guard ingestLoggingEnabled != enabled else { return }
        ingestLoggingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.ingestLoggingDefaultsKey)
    }

    func clearIngestLog() {
        do {
            try IngestLogStore.clear()
            ingestLogEntryCount = 0
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(localized: "Failed to clear ingest log")
        }
    }

    /// Raw JSONL for pasting into a bug report.
    func copyIngestLogJSONL() -> String? {
        do {
            let data = try IngestLogStore.exportJSONL()
            guard !data.isEmpty else { return "" }
            return String(data: data, encoding: .utf8)
        } catch {
            lastErrorMessage = String(localized: "Failed to read ingest log")
            return nil
        }
    }

    func refreshIngestLogCount() {
        ingestLogEntryCount = (try? IngestLogStore.count()) ?? 0
    }

    private func recordIngestDrain(count: Int) {
        guard ingestLoggingEnabled else { return }
        appendIngestLog(
            IngestLogEntry(
                kind: "drain",
                outcome: "summary",
                detail: "count=\(count)",
                activeSessionCount: activeSessionCount()
            )
        )
    }

    private func recordIngestEvent(
        at date: Date,
        source: HookIngestSource,
        queuedAt: Date?,
        eventName: String?,
        activity: String?,
        outcome: String,
        detail: String?,
        parsed: ParsedHookLine?
    ) {
        guard ingestLoggingEnabled else { return }
        appendIngestLog(
            IngestLogEntry(
                at: date,
                kind: "event",
                source: source.rawValue,
                queuedAt: queuedAt,
                eventName: eventName,
                agent: parsed?.session.agent.rawValue,
                conversationID: parsed?.session.conversationID,
                projectName: parsed?.projectName,
                modelName: parsed?.modelName,
                isSubagent: parsed?.isSubagent,
                activity: activity,
                outcome: outcome,
                detail: detail,
                activeSessionCount: activeSessionCount()
            )
        )
    }

    private func appendIngestLog(_ entry: IngestLogEntry) {
        do {
            try IngestLogStore.append(entry)
            ingestLogEntryCount = (try? IngestLogStore.count()) ?? (ingestLogEntryCount + 1)
        } catch {
            // Diagnostics must stay fail-open; never break hook handling.
        }
    }

    private func activeSessionCount() -> Int {
        world.sessions.values.reduce(0) { partial, snapshot in
            partial + (snapshot.activity == .idle ? 0 : 1)
        }
    }

    private static func activityLabel(for transition: StateTransition) -> String {
        switch transition {
        case .removeSession:
            return "removeSession"
        case let .apply(activity):
            switch activity {
            case .idle: return "idle"
            case .registered: return "registered"
            case .thinking: return "thinking"
            case let .usingTool(name): return "usingTool:\(name)"
            case .responding: return "responding"
            case .waiting: return "waiting"
            case .done: return "done"
            case .interrupted: return "interrupted"
            case .failed: return "failed"
            }
        }
    }

    private static func rawHookEventName(from jsonLine: String) -> String? {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let name = object["hook_event_name"] as? String, !name.isEmpty { return name }
        if let name = object["hookEventName"] as? String, !name.isEmpty { return name }
        return nil
    }
    #endif

    private func handle(
        jsonLine: String,
        at date: Date,
        source: HookIngestSource,
        queuedAt: Date?
    ) {
        do {
            guard let parsed = try HookLineParser.parse(jsonLine: jsonLine) else {
                #if DEBUG
                recordIngestEvent(
                    at: date,
                    source: source,
                    queuedAt: queuedAt,
                    eventName: Self.rawHookEventName(from: jsonLine),
                    activity: nil,
                    outcome: "ignored",
                    detail: "unparsed",
                    parsed: nil
                )
                #endif
                return
            }
            #if DEBUG
            debugBubbleItems = []
            #endif
            mergeDisplayMeta(
                for: parsed.session,
                projectName: parsed.projectName,
                modelName: parsed.modelName,
                isSubagent: parsed.isSubagent
            )
            if case .removeSession = parsed.transition {
                sessionDisplayMeta.removeValue(forKey: parsed.session)
                sessionHookEvents.removeValue(forKey: parsed.session)
            } else if case .apply = parsed.transition {
                sessionHookEvents[parsed.session] = parsed.eventName
            }
            apply(
                .agent(session: parsed.session, transition: parsed.transition, at: date)
            )
            #if DEBUG
            recordIngestEvent(
                at: date,
                source: source,
                queuedAt: queuedAt,
                eventName: parsed.eventName,
                activity: Self.activityLabel(for: parsed.transition),
                outcome: "applied",
                detail: nil,
                parsed: parsed
            )
            #endif
            scheduleWatchdog()
            if case let .apply(activity) = parsed.transition,
               PetStateMachine.schedulesIdleFallback(activity)
            {
                scheduleIdleDeadline()
            }
        } catch {
            // Malformed hook payloads are ignored; agents are fail-open and so are we.
            #if DEBUG
            recordIngestEvent(
                at: date,
                source: source,
                queuedAt: queuedAt,
                eventName: Self.rawHookEventName(from: jsonLine),
                activity: nil,
                outcome: "malformed",
                detail: String(describing: error),
                parsed: nil
            )
            #endif
        }
    }

    private func mergeDisplayMeta(
        for session: SessionKey,
        projectName: String?,
        modelName: String?,
        isSubagent: Bool = false
    ) {
        guard projectName != nil || modelName != nil || isSubagent else { return }
        var meta = sessionDisplayMeta[session] ?? SessionDisplayMeta()
        if let projectName { meta.projectName = projectName }
        if let modelName { meta.modelName = modelName }
        // Sticky: once marked a subagent, keep the outline capsule for the session.
        if isSubagent { meta.isSubagent = true }
        sessionDisplayMeta[session] = meta
    }

    private func apply(_ event: PetEvent) {
        world = PetStateMachine.reduce(world, event: event)
        syncCursorUsingToolStallTimers()
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    private func refreshBubbleItems() {
        let now = Date()
        var items: [StatusBubbleItem] = []
        for (key, snapshot) in world.sessions {
            if snapshot.activity == .idle {
                sessionDisplayMeta.removeValue(forKey: key)
                continue
            }
            let isAwaitingApproval = snapshot.activity == .waiting
            let isStalledUsingTool = CursorUsingToolStallHint.isDue(
                agent: key.agent,
                activity: snapshot.activity,
                lastEventAt: snapshot.lastEventAt,
                now: now
            )
            let showsAttentionCTA = isAwaitingApproval || isStalledUsingTool
            guard let phrase = StatusCopy.statusPhrase(for: snapshot.activity) else { continue }
            let text = isStalledUsingTool ? StatusCopy.stuckPhrase : phrase
            let meta = sessionDisplayMeta[key]
            let isSubagent = meta?.isSubagent == true
            items.append(
                StatusBubbleItem(
                    id: "\(key.agent.rawValue):\(key.conversationID)",
                    text: text,
                    lastEventAt: snapshot.lastEventAt,
                    isDismissible: snapshot.activity == .failed,
                    animatesEllipsis: !showsAttentionCTA && Self.animatesEllipsis(for: snapshot.activity),
                    isAwaitingApproval: showsAttentionCTA,
                    agentName: isSubagent ? "Subagent" : StatusCopy.displayName(key.agent),
                    iconAssetName: Self.iconAssetName(for: key.agent),
                    projectName: meta?.projectName,
                    modelName: meta?.modelName,
                    isSubagent: isSubagent,
                    agent: key.agent
                )
            )
        }
        items.append(contentsOf: webhookBubbles)
        if let tunnelWarningBubble {
            items.append(tunnelWarningBubble)
        }
        #if DEBUG
        items.append(contentsOf: debugBubbleItems)
        #endif
        let next = items.sorted { $0.lastEventAt > $1.lastEventAt }
        let oldIDs = Set(bubbleItems.map(\.id))
        let newIDs = Set(next.map(\.id))
        guard oldIDs != newIDs else {
            bubbleItems = next
            return
        }
        // Only animate the assignment for pure removals (Pow poof). Inserts are
        // driven by AnimatedStatusBubble.onAppear — wrapping inserts in
        // withAnimation fights the initial @State and can zero the NSPanel.
        let onlyRemovals = newIDs.isSubset(of: oldIDs)
        if onlyRemovals {
            withAnimation(BubbleMotion.disappear) {
                bubbleItems = next
            }
        } else {
            bubbleItems = next
        }
    }

    private static func iconAssetName(for agent: AgentKind) -> String? {
        switch agent {
        case .cursor: "cursor"
        case .codex: "codex"
        }
    }

    /// Terminal / approval statuses keep static copy — no loading-dot cycle.
    private static func animatesEllipsis(for activity: PetActivityState) -> Bool {
        switch activity {
        case .done, .interrupted, .waiting: false
        default: true
        }
    }

    private func scheduleWebhookExpiry(for id: String, seconds: Int) {
        cancelWebhookExpiry(for: id)
        let delay = max(1, seconds)
        webhookExpiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.removeWebhookBubble(id: id)
            }
        }
    }

    private func cancelWebhookExpiry(for id: String) {
        webhookExpiryTasks[id]?.cancel()
        webhookExpiryTasks[id] = nil
    }

    private func removeWebhookBubble(id: String) {
        cancelWebhookExpiry(for: id)
        let before = webhookBubbles.count
        webhookBubbles.removeAll { $0.id == id }
        guard webhookBubbles.count != before else { return }
        refreshBubbleItems()
        PetPanelController.shared.refreshContent()
    }

    private func scheduleIdleDeadline() {
        idleTask?.cancel()
        let now = Date()
        guard let nextDeadline = world.sessions.values.compactMap(\.idleAt).min() else { return }
        let delay = max(0, nextDeadline.timeIntervalSince(now))
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.apply(.idleDeadline(at: Date()))
                // Other sessions may still have a later `idleAt` (e.g. responding @ 60s).
                if self.world.sessions.values.contains(where: { $0.idleAt != nil }) {
                    self.scheduleIdleDeadline()
                }
            }
        }
    }

    /// One-shot wake-ups so Cursor `.usingTool` stall CTAs appear without polling.
    private func syncCursorUsingToolStallTimers() {
        let now = Date()
        var active = Set<SessionKey>()
        for (key, snapshot) in world.sessions {
            guard key.agent == .cursor, case .usingTool = snapshot.activity else { continue }
            active.insert(key)
            let fireAt = snapshot.lastEventAt.addingTimeInterval(CursorUsingToolStallHint.delay)
            let delay = fireAt.timeIntervalSince(now)
            cancelCursorUsingToolStallTask(for: key)
            // Already due — `refreshBubbleItems` derives the CTA from `lastEventAt`.
            guard delay > 0 else { continue }
            let expectedLastEventAt = snapshot.lastEventAt
            cursorUsingToolStallTasks[key] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard let current = self.world.sessions[key],
                          case .usingTool = current.activity,
                          current.lastEventAt == expectedLastEventAt
                    else { return }
                    self.cursorUsingToolStallTasks[key] = nil
                    self.refreshBubbleItems()
                    PetPanelController.shared.refreshContent()
                }
            }
        }
        for key in cursorUsingToolStallTasks.keys where !active.contains(key) {
            cancelCursorUsingToolStallTask(for: key)
        }
    }

    private func cancelCursorUsingToolStallTask(for key: SessionKey) {
        cursorUsingToolStallTasks[key]?.cancel()
        cursorUsingToolStallTasks[key] = nil
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
