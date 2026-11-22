import AiboCore
import AiboIngest
import AppKit
import Darwin
import Foundation

/// Settings-process side of the pipe link back to the main Aibo process.
@MainActor
@Observable
final class SettingsProcessClient {
    static let shared = SettingsProcessClient()

    /// Mirrored debug toggle so DevelopmentSettingsPane never instantiates `AiboPanelController`.
    private(set) var showHitRegionDebug = false

    private var channel: SettingsPipeChannel?
    private var nextRequestID: UInt64 = 1
    private var pendingReplies: [UInt64: CheckedContinuation<SettingsRPCReply, Never>] = [:]
    private var isClosing = false
    private var closeCompletion: (() -> Void)?
    private var closeTimeoutTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard AppProcessRole.isSettings else { return }
        guard let fds = AppProcessRole.settingsPipeFDs else {
            // Launched manually with `--role=settings` without a parent pipe.
            NSApp.terminate(nil)
            return
        }

        let link = SettingsPipeChannel(
            readFD: fds.readFD,
            writeFD: fds.writeFD,
            onFrame: { data in
                guard let message = try? JSONDecoder().decode(MainToSettingsMessage.self, from: data) else {
                    return
                }
                Task { @MainActor in
                    SettingsProcessClient.shared.handleIncoming(message)
                }
            },
            onClose: {
                Task { @MainActor in
                    SettingsProcessClient.shared.handleDisconnected()
                }
            }
        )
        self.channel = link
        link.start()
    }

    func sendRememberPane(_ id: String?) {
        guard AppProcessRole.isSettings, !isClosing else { return }
        channel?.send(SettingsToMainMessage.rememberPane(id: id))
    }

    func sendPreferences(_ wire: SettingsAppPreferencesWire) {
        guard AppProcessRole.isSettings, !isClosing else { return }
        channel?.send(SettingsToMainMessage.preferences(wire))
    }

    func sendLibrary(_ mutation: SettingsLibraryMutation) {
        guard AppProcessRole.isSettings, !isClosing else { return }
        channel?.send(SettingsToMainMessage.library(mutation))
    }

    func sendCommand(_ command: SettingsCommand) {
        guard AppProcessRole.isSettings, !isClosing else { return }
        channel?.send(SettingsToMainMessage.command(command))
    }

    func sendOpenURLs(_ urls: [URL]) {
        guard AppProcessRole.isSettings, !isClosing else { return }
        channel?.send(SettingsToMainMessage.openURLs(urls.map(\.absoluteString)))
    }

    func setShowHitRegionDebug(_ enabled: Bool) {
        showHitRegionDebug = enabled
        sendCommand(.debugSetShowHitRegion(enabled))
    }

    func request(_ request: SettingsRPCRequest) async -> SettingsRPCReply {
        guard AppProcessRole.isSettings, let channel, !isClosing else {
            return .failed("Settings is not connected to Aibo.")
        }
        let id = nextRequestID
        nextRequestID &+= 1
        return await withCheckedContinuation { continuation in
            pendingReplies[id] = continuation
            channel.send(SettingsToMainMessage.request(id: id, request: request))
        }
    }

    /// Called when the Settings window closes: flushes pending edits to main and exits.
    func beginGracefulCloseAndExit() {
        guard AppProcessRole.isSettings else { return }
        if !prepareForTermination(reply: {
            Darwin.exit(0)
        }) {
            Darwin.exit(0)
        }
    }

    /// Sends `.closing` and waits up to 1 second for `.readyToClose` before invoking `reply`.
    func prepareForTermination(reply: @escaping () -> Void) -> Bool {
        guard AppProcessRole.isSettings else { return false }
        guard let channel, !isClosing else { return false }
        isClosing = true
        closeCompletion = reply
        channel.send(SettingsToMainMessage.closing)
        closeTimeoutTask?.cancel()
        closeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.finishClose()
        }
        return true
    }

    // MARK: - Incoming Messages

    private func handleIncoming(_ message: MainToSettingsMessage) {
        switch message {
        case .show(let destination, let rememberedPaneID):
            SettingsNavigator.shared.applyRemoteShow(
                destination: destination,
                rememberedPaneID: rememberedPaneID
            )
            SettingsWindowController.shared.show()
            channel?.send(SettingsToMainMessage.ready(pid: getpid()))

        case .snapshot(let snapshot):
            applySnapshot(snapshot)

        case .preferences(let wire):
            AppSettings.shared.applyRemotePreferencesWire(wire)

        case .libraryReload:
            AiboLibraryStore.shared.reloadFromRemoteDiskChange()

        case .extensionsReload:
            ExtensionCenter.shared.reload()

        case .hookSpritesReload:
            HookSpriteSettings.shared.reloadFromDefaults()

        case .actionSpritesReload:
            AiboActionSettings.shared.reloadFromDefaults()

        case .reply(let id, let reply):
            if let continuation = pendingReplies.removeValue(forKey: id) {
                continuation.resume(returning: reply)
            }

        case .readyToClose:
            finishClose()

        case .terminate:
            failPendingReplies()
            channel?.close()
            channel = nil
            Darwin.exit(0)
        }
    }

    private func applySnapshot(_ snapshot: SettingsMainSnapshot) {
        showHitRegionDebug = snapshot.showHitRegionDebug
        AiboRuntime.shared.applyMirroredSnapshot(snapshot)
        SoftwareUpdateController.shared.applyMirroredSnapshot(snapshot)
        KeystrokeMonitor.shared.applyMirroredAccessibilityTrusted(snapshot.keystrokeAccessibilityTrusted)
        PlaytimeStore.shared.applyMirroredState(
            snapshot: snapshot.playtimeSnapshot,
            daily: snapshot.playtimeDaily
        )
        MusicPlaybackMonitor.shared.applyMirroredSnapshot(snapshot)
    }

    private func handleDisconnected() {
        failPendingReplies()
        channel = nil
        if closeCompletion != nil {
            finishClose()
        } else {
            Darwin.exit(0)
        }
    }

    private func finishClose() {
        closeTimeoutTask?.cancel()
        closeTimeoutTask = nil
        failPendingReplies()
        channel?.close()
        channel = nil
        let completion = closeCompletion
        closeCompletion = nil
        completion?()
    }

    private func failPendingReplies() {
        let pending = pendingReplies
        pendingReplies.removeAll()
        for (_, continuation) in pending {
            continuation.resume(returning: .failed("Lost connection to Aibo."))
        }
    }
}
