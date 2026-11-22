import AiboCore
import AiboIngest
import AppKit
import Darwin
import Foundation
import Observation

/// Main-process coordinator for the out-of-process Settings instance (`--role=settings`).
///
/// The main app remains the single hub for all background engines, desktop UI,
/// and authoritative state. While Settings is open, changes sync in both
/// directions over a framed `stdin`/`stdout` pipe; when Settings closes, the
/// child process exits and returns all Settings UI / AutoFill memory to macOS.
@MainActor
final class SettingsProcessHost {
    static let shared = SettingsProcessHost()

    private var process: Process?
    private var channel: SettingsPipeChannel?
    private var childPID: Int32?
    private var isClosing = false
    private var inFlightRPCCount = 0
    private var sessionGeneration: UInt64 = 0
    private var snapshotCoalesceTask: Task<Void, Never>?
    private var lastSentSnapshot: SettingsMainSnapshot?
    private var retiringChannels: [UInt64: SettingsPipeChannel] = [:]
    private var retiringProcesses: [UInt64: Process] = [:]
    private var retiringKillTasks: [UInt64: Task<Void, Never>] = [:]

    private init() {}

    var isSettingsRunning: Bool {
        channel != nil && !isClosing
    }

    func open(destination: SettingsShowDestination) {
        guard AppProcessRole.isMain else { return }

        if let channel, !isClosing {
            channel.send(MainToSettingsMessage.show(
                destination: destination,
                rememberedPaneID: SettingsNavigator.shared.rememberedPaneID
            ))
            handOffFocusToChild()
            return
        }

        if isClosing {
            retireActiveSession()
        }

        guard executableMatchesDisk() else {
            presentExecutableReplacedAlert()
            return
        }

        spawnSettingsProcess(initialDestination: destination)
    }

    func notifyPreferencesChanged() {
        guard AppProcessRole.isMain, let channel, !isClosing else { return }
        channel.send(MainToSettingsMessage.preferences(AppSettings.shared.syncPreferencesWire()))
    }

    func notifyLibraryChanged() {
        guard AppProcessRole.isMain, let channel, !isClosing else { return }
        channel.send(MainToSettingsMessage.libraryReload)
    }

    func notifyExtensionsChanged() {
        guard AppProcessRole.isMain, let channel, !isClosing else { return }
        channel.send(MainToSettingsMessage.extensionsReload)
    }

    func notifyHookSpritesChanged() {
        guard AppProcessRole.isMain, let channel, !isClosing else { return }
        channel.send(MainToSettingsMessage.hookSpritesReload)
    }

    func notifyActionSpritesChanged() {
        guard AppProcessRole.isMain, let channel, !isClosing else { return }
        channel.send(MainToSettingsMessage.actionSpritesReload)
    }

    func terminateForAppQuit() {
        guard AppProcessRole.isMain else { return }
        let activeProcess = process
        let activeChannel = channel
        activeChannel?.send(MainToSettingsMessage.terminate)
        teardownActiveSession()
        if let activeProcess, activeProcess.isRunning {
            activeProcess.terminate()
        }
        for (_, task) in retiringKillTasks {
            task.cancel()
        }
        retiringKillTasks.removeAll()
        for (_, retiring) in retiringChannels {
            retiring.send(MainToSettingsMessage.terminate)
            retiring.close()
        }
        retiringChannels.removeAll()
        for (_, retiringProcess) in retiringProcesses where retiringProcess.isRunning {
            retiringProcess.terminate()
        }
        retiringProcesses.removeAll()
    }

    // MARK: - Spawn & Lifecycle

    private func spawnSettingsProcess(initialDestination: SettingsShowDestination) {
        guard let executableURL = Bundle.main.executableURL else { return }

        let toChild = Pipe()
        let fromChild = Pipe()
        let child = Process()
        child.executableURL = executableURL
        child.arguments = [SettingsProcessRole.settingsArgument]
        child.standardInput = toChild
        child.standardOutput = fromChild
        child.standardError = FileHandle.standardError

        do {
            try child.run()
        } catch {
            try? toChild.fileHandleForReading.close()
            try? toChild.fileHandleForWriting.close()
            try? fromChild.fileHandleForReading.close()
            try? fromChild.fileHandleForWriting.close()
            return
        }

        // Close the child-owned ends in the parent immediately.
        try? toChild.fileHandleForReading.close()
        try? fromChild.fileHandleForWriting.close()

        // Duplicate parent ends so SettingsPipeChannel owns its FDs independently
        // from Foundation's FileHandle deinit.
        let readFD = dup(fromChild.fileHandleForReading.fileDescriptor)
        let writeFD = dup(toChild.fileHandleForWriting.fileDescriptor)
        try? fromChild.fileHandleForReading.close()
        try? toChild.fileHandleForWriting.close()

        guard readFD >= 0, writeFD >= 0 else {
            if readFD >= 0 { Darwin.close(readFD) }
            if writeFD >= 0 { Darwin.close(writeFD) }
            child.terminate()
            return
        }

        sessionGeneration &+= 1
        let generation = sessionGeneration
        self.process = child
        self.childPID = child.processIdentifier
        self.isClosing = false
        self.lastSentSnapshot = nil

        let link = SettingsPipeChannel(
            readFD: readFD,
            writeFD: writeFD,
            onFrame: { data in
                guard let message = try? JSONDecoder().decode(SettingsToMainMessage.self, from: data) else {
                    return
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        SettingsProcessHost.shared.handleIncoming(message, generation: generation)
                    }
                }
            },
            onClose: {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        SettingsProcessHost.shared.handleChannelClosed(generation: generation)
                    }
                }
            }
        )
        self.channel = link
        link.start()

        // Seed state before telling Settings to show the window.
        link.send(MainToSettingsMessage.preferences(AppSettings.shared.syncPreferencesWire()))
        observeAndSendSnapshot(generation: generation)
        link.send(MainToSettingsMessage.show(
            destination: initialDestination,
            rememberedPaneID: SettingsNavigator.shared.rememberedPaneID
        ))
    }

    private func retireActiveSession() {
        let retiringGeneration = sessionGeneration
        snapshotCoalesceTask?.cancel()
        snapshotCoalesceTask = nil
        lastSentSnapshot = nil
        if let activeChannel = channel {
            retiringChannels[retiringGeneration] = activeChannel
        }
        if let activeProcess = process {
            retiringProcesses[retiringGeneration] = activeProcess
            retiringKillTasks[retiringGeneration] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if let hung = self.retiringProcesses.removeValue(forKey: retiringGeneration),
                   hung.isRunning
                {
                    hung.terminate()
                }
                if let ch = self.retiringChannels.removeValue(forKey: retiringGeneration) {
                    ch.close()
                }
                self.retiringKillTasks.removeValue(forKey: retiringGeneration)
            }
        }
        process = nil
        channel = nil
        childPID = nil
        isClosing = false
        inFlightRPCCount = 0
    }

    private func teardownActiveSession() {
        sessionGeneration &+= 1
        snapshotCoalesceTask?.cancel()
        snapshotCoalesceTask = nil
        lastSentSnapshot = nil
        channel?.close()
        channel = nil
        process = nil
        childPID = nil
        isClosing = false
        inFlightRPCCount = 0
    }

    private func handleChannelClosed(generation: UInt64) {
        if generation == sessionGeneration {
            snapshotCoalesceTask?.cancel()
            snapshotCoalesceTask = nil
            lastSentSnapshot = nil
            channel = nil
            process = nil
            childPID = nil
            isClosing = false
            inFlightRPCCount = 0
        } else {
            retiringChannels.removeValue(forKey: generation)
            retiringProcesses.removeValue(forKey: generation)
            retiringKillTasks.removeValue(forKey: generation)?.cancel()
        }
    }

    private func handOffFocusToChild() {
        guard let pid = childPID,
              let app = NSRunningApplication(processIdentifier: pid)
        else { return }
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }

    // MARK: - Snapshot Observation

    private func observeAndSendSnapshot(generation: UInt64) {
        guard generation == sessionGeneration, channel != nil, !isClosing else { return }

        let snapshot = withObservationTracking {
            makeSnapshot()
        } onChange: {
            Task { @MainActor in
                SettingsProcessHost.shared.scheduleSnapshotRefresh(generation: generation)
            }
        }

        if snapshot != lastSentSnapshot {
            lastSentSnapshot = snapshot
            channel?.send(MainToSettingsMessage.snapshot(snapshot))
        }
    }

    private func scheduleSnapshotRefresh(generation: UInt64) {
        guard generation == sessionGeneration, channel != nil, !isClosing else { return }
        guard snapshotCoalesceTask == nil else { return }
        snapshotCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, self.sessionGeneration == generation else { return }
            self.snapshotCoalesceTask = nil
            self.observeAndSendSnapshot(generation: generation)
        }
    }

    private func makeSnapshot() -> SettingsMainSnapshot {
        let runtime = AiboRuntime.shared
        let updates = SoftwareUpdateController.shared
        let keystrokes = KeystrokeMonitor.shared
        let playtime = PlaytimeStore.shared
        let music = MusicPlaybackMonitor.shared

        #if DEBUG
        let showHitRegion = AiboPanelController.shared.showHitRegionDebug
        let musicForcePlaying = music.debugForcePlaying
        let mediaRemoteCount = music.debugMediaRemoteUpdateCount
        let mediaRemoteDump = music.debugLastMediaRemoteDump
        #else
        let showHitRegion = false
        let musicForcePlaying = false
        let mediaRemoteCount = 0
        let mediaRemoteDump = "(no update yet)"
        #endif

        return SettingsMainSnapshot(
            cursorHooksInstalled: runtime.cursorHooksInstalled,
            codexHooksInstalled: runtime.codexHooksInstalled,
            deepseekPluginInstalled: runtime.deepseekPluginInstalled,
            antigravityHooksInstalled: runtime.antigravityHooksInstalled,
            cursorHostAppInstalled: runtime.cursorHostAppInstalled,
            codexHostAppInstalled: runtime.codexHostAppInstalled,
            antigravityHostAppInstalled: runtime.antigravityHostAppInstalled,
            webhookListening: runtime.webhookListening,
            tunnelHealthStatus: runtime.tunnelHealthStatus.wireValue,
            lastRuntimeErrorMessage: runtime.lastErrorMessage,
            ingestLoggingEnabled: runtime.ingestLoggingEnabled,
            ingestLogEntryCount: runtime.ingestLogEntryCount,
            receiveLogEntries: runtime.receiveLogEntries,
            receiveLogTotalCount: runtime.receiveLogTotalCount,
            hasUpdateFeed: updates.hasUpdateFeed,
            canCheckForUpdates: updates.canCheckForUpdates,
            automaticallyChecksForUpdates: updates.automaticallyChecksForUpdates,
            availableUpdateDisplayVersion: updates.availableUpdateDisplayVersion,
            keystrokeAccessibilityTrusted: keystrokes.accessibilityTrusted,
            playtimeSnapshot: playtime.snapshot,
            playtimeDaily: playtime.daily,
            showHitRegionDebug: showHitRegion,
            musicDebugForcePlaying: musicForcePlaying,
            musicIsPlaying: music.isPlaying,
            mediaRemoteUpdateCount: mediaRemoteCount,
            mediaRemoteLastDump: mediaRemoteDump
        )
    }

    // MARK: - Incoming Messages

    private func handleIncoming(_ message: SettingsToMainMessage, generation: UInt64) {
        guard generation == sessionGeneration else { return }

        switch message {
        case .ready(let pid):
            childPID = pid
            handOffFocusToChild()

        case .rememberPane(let id):
            SettingsNavigator.shared.rememberPane(id: id)

        case .preferences(let wire):
            AppSettings.shared.applyRemotePreferencesWire(wire)

        case .library(let mutation):
            applyLibraryMutation(mutation)

        case .command(let command):
            applyCommand(command)

        case .request(let id, let request):
            inFlightRPCCount += 1
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reply = await self.handleRPC(request)
                guard self.sessionGeneration == generation else { return }
                self.channel?.send(MainToSettingsMessage.reply(id: id, reply: reply))
                self.inFlightRPCCount = max(0, self.inFlightRPCCount - 1)
                if self.isClosing, self.inFlightRPCCount == 0 {
                    self.channel?.send(MainToSettingsMessage.readyToClose)
                }
            }

        case .openURLs(let rawURLs):
            let urls = rawURLs.compactMap { URL(string: $0) }
            guard !urls.isEmpty else { return }
            NSApp.delegate?.application?(NSApp, open: urls)

        case .closing:
            isClosing = true
            snapshotCoalesceTask?.cancel()
            snapshotCoalesceTask = nil
            AiboLibraryStore.shared.flushPendingPersist()
            if inFlightRPCCount == 0 {
                channel?.send(MainToSettingsMessage.readyToClose)
            }
        }
    }

    private func applyLibraryMutation(_ mutation: SettingsLibraryMutation) {
        let library = AiboLibraryStore.shared
        switch mutation {
        case .select(let id):
            library.select(id: id)
        case .setScalePercent(let percent):
            library.setScalePercent(percent)
        case .setBubbleDistance(let distance):
            library.setBubbleDistance(distance)
        case .setBubblePlacement(let placement):
            library.setBubblePlacement(placement)
        case .setPixelOptimization(let enabled):
            library.setPixelOptimizationEnabled(enabled)
        case .rename(let id, let name):
            _ = library.rename(id: id, to: name)
        case .remove(let ids):
            library.remove(ids: ids)
        case .reloadAfterDiskImport(let installedID):
            library.adoptInstalledRecordFromSettingsProcess(id: installedID)
        }
    }

    private func applyCommand(_ command: SettingsCommand) {
        switch command {
        case .refreshHostAppPresence:
            AiboRuntime.shared.refreshHostAppPresence()
        case .refreshHookInstallation:
            AiboRuntime.shared.refreshHookInstallation()
        case .recheckAccessibility:
            KeystrokeMonitor.shared.recheckAccessibility()
        case .installHooks(let agent):
            AiboRuntime.shared.installHooks(for: agent)
        case .uninstallHooks(let agent):
            AiboRuntime.shared.uninstallHooks(for: agent)
        case .scheduleTunnelCheck:
            TunnelHealthMonitor.shared.scheduleCheck(reason: .manual)
        case .clearReceiveLog:
            AiboRuntime.shared.clearReceiveLog()
        case .regenerateWebhookSecret:
            AppSettings.shared.regenerateWebhookSecret()
        case .setIngestLoggingEnabled(let enabled):
            AiboRuntime.shared.setIngestLoggingEnabled(enabled)
        case .refreshIngestLogCount:
            AiboRuntime.shared.refreshIngestLogCount()
        case .clearIngestLog:
            AiboRuntime.shared.clearIngestLog()
        case .checkForUpdates:
            SoftwareUpdateController.shared.checkForUpdates()
        case .setAutomaticallyChecksForUpdates(let enabled):
            SoftwareUpdateController.shared.setAutomaticallyChecksForUpdates(enabled)
        case .reloadExtensions:
            ExtensionCenter.shared.reloadAfterSettingsEdit()
        case .hookSpriteMappingChanged:
            HookSpriteSettings.shared.reloadFromDefaults()
            AiboRuntime.shared.noteHookSpriteMappingChanged()
        case .actionSpriteMappingChanged:
            AiboActionSettings.shared.reloadFromDefaults()
        case .relaunchMainApp:
            AppSettings.relaunchApplication()

        case .debugShowBubble(let payload):
            #if DEBUG
            AiboRuntime.shared.showDebugBubble(
                text: payload.text,
                agentName: payload.agentName,
                projectName: payload.projectName,
                modelName: payload.modelName,
                showCursorIcon: payload.showCursorIcon,
                isSubagent: payload.isSubagent,
                stack: payload.stack,
                isAwaitingApproval: payload.isAwaitingApproval,
                showsPlanProgress: payload.showsPlanProgress,
                planProgressIntervalSeconds: payload.planProgressIntervalSeconds
            )
            #endif
        case .debugShowTunnelWarningBubble:
            #if DEBUG
            AiboRuntime.shared.showDebugTunnelWarningBubble()
            #endif
        case .debugClearBubble:
            #if DEBUG
            AiboRuntime.shared.clearDebugBubble()
            #endif
        case .debugReplayOnboarding:
            #if DEBUG
            OnboardingController.shared.replay()
            #endif
        case .debugReplayLaunchPortal:
            #if DEBUG
            AiboPanelController.shared.replayLaunchPortal()
            #endif
        case .debugSetShowHitRegion(let enabled):
            #if DEBUG
            AiboPanelController.shared.showHitRegionDebug = enabled
            #endif
        case .debugSetMusicForcePlaying(let enabled):
            #if DEBUG
            MusicPlaybackMonitor.shared.debugForcePlaying = enabled
            #endif
        case .debugFetchMediaRemoteOnce:
            #if DEBUG
            MusicPlaybackMonitor.shared.debugFetchMediaRemoteOnce()
            #endif
        case .debugTriggerDodge:
            #if DEBUG
            AiboPanelController.shared.debugTriggerDodge()
            #endif
        case .debugMouseShakeConfigChanged(let config):
            #if DEBUG
            MouseShakeDebugSettings.shared.applyRemoteConfig(config)
            #endif
        case .debugPresentExtensionWindow(let running):
            #if DEBUG
            ExtensionCenter.shared.presentDebugWindow(running: running)
            #endif
        case .debugIngestWebhookBody(let data):
            #if DEBUG
            AiboRuntime.shared.ingestWebhookBody(data)
            #endif
        case .debugShowAvailableUpdate:
            #if DEBUG
            SoftwareUpdateController.shared.debugShowAvailableUpdate()
            #endif
        case .debugShowUpToDate:
            #if DEBUG
            SoftwareUpdateController.shared.debugShowUpToDate()
            #endif
        case .debugClearUpdatePreview:
            #if DEBUG
            SoftwareUpdateController.shared.debugClearPreview()
            #endif
        }
    }

    private func handleRPC(_ request: SettingsRPCRequest) async -> SettingsRPCReply {
        switch request {
        case .prepareBackupExport(let includeHookLog):
            let playtime = PlaytimeStore.shared.ledgerForExport()
            if includeHookLog {
                do {
                    let tempURL = try AiboRuntime.shared.copyIngestLogForBackup()
                    return .backupExportPrepared(playtime: playtime, hookLogTempPath: tempURL?.path)
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            return .backupExportPrepared(playtime: playtime, hookLogTempPath: nil)

        case .finishBackupImport(let hookLogPath, let playtimeFile, let playtimeMode, let applySettings):
            if let hookLogPath {
                do {
                    try AiboRuntime.shared.importIngestLog(from: URL(fileURLWithPath: hookLogPath))
                } catch {
                    // Settings will restore the previous library on disk; keep Main's in-memory library intact.
                    return .backupImportFinished(errorMessage: error.localizedDescription)
                }
            }
            AiboLibraryStore.shared.adoptImportedLibrary()
            if playtimeMode != .skip {
                PlaytimeStore.shared.importBackup(playtimeFile, mode: playtimeMode)
            }
            if let settings = applySettings {
                let settingsModel = AppSettings.shared
                settingsModel.applyBackup(settings)
                if settingsModel.restoreLastAiboPosition,
                   let x = settingsModel.savedAiboCenterXPercent,
                   let y = settingsModel.savedAiboCenterYPercent
                {
                    AiboPanelController.shared.placeAiboAtRelativePosition(xPercent: x, yPercent: y)
                }
            }
            return .backupImportFinished(errorMessage: nil)

        case .postTestWebhook(let body):
            #if DEBUG
            let error = await AiboRuntime.shared.postTestWebhook(body: body)
            return .testWebhookResult(errorMessage: error)
            #else
            return .testWebhookResult(errorMessage: nil)
            #endif

        case .exportReceiveLog:
            return .receiveLogData(AiboRuntime.shared.exportReceiveLog())

        case .copyIngestLogJSONL:
            return .ingestLogJSONL(AiboRuntime.shared.copyIngestLogJSONL())
        }
    }

    // MARK: - Executable Identity Guard

    private func executableMatchesDisk() -> Bool {
        guard let launched = AppProcessRole.launchedExecutable else { return true }
        return launched.matchesCurrentOnDisk()
    }

    private func presentExecutableReplacedAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Relaunch Aibo to Open Settings")
        alert.informativeText = String(localized: "Aibo was updated on disk while running. Relaunch it to continue.")
        alert.addButton(withTitle: String(localized: "Relaunch"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            AppSettings.relaunchApplication()
        }
    }
}
