import AppKit
import Foundation

/// Built-in players that post well-known `NSDistributedNotificationCenter` names.
/// Most Chinese clients (NetEase, QQ Music, …) do not — use custom names in Settings.
enum BuiltInMusicNotification: String, CaseIterable, Sendable {
    case appleMusic
    case iTunesLegacy
    case spotify

    var notificationName: String {
        switch self {
        case .appleMusic: "com.apple.Music.playerInfo"
        case .iTunesLegacy: "com.apple.iTunes.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        }
    }

    /// Bundle IDs used to clear "playing" when the app quits without a pause event.
    var bundleIDs: Set<String> {
        switch self {
        case .appleMusic, .iTunesLegacy: ["com.apple.Music", "com.apple.iTunes"]
        case .spotify: ["com.spotify.client"]
        }
    }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .iTunesLegacy: "iTunes (legacy)"
        case .spotify: "Spotify"
        }
    }
}

/// Parses common now-playing distributed-notification payloads.
/// `nonisolated` so Sendable notification observers can parse off the main actor.
nonisolated enum MusicPlaybackPayload {
    /// Returns whether the payload indicates active playback.
    static func isPlaying(userInfo: [AnyHashable: Any]?) -> Bool {
        guard let userInfo, !userInfo.isEmpty else { return false }

        if let state = stringValue(userInfo["Player State"])
            ?? stringValue(userInfo["playerState"])
            ?? stringValue(userInfo["PlaybackState"])
            ?? stringValue(userInfo["playbackState"])
        {
            let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "playing" || normalized == "play" { return true }
            if normalized == "paused"
                || normalized == "pause"
                || normalized == "stopped"
                || normalized == "stop"
                || normalized == "interrupted"
            {
                return false
            }
        }

        if let playing = boolValue(userInfo["playing"]) ?? boolValue(userInfo["Playing"]) {
            return playing
        }

        return false
    }

    private static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let value as String: value
        case let value as NSString: value as String
        default: nil
        }
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "playing": true
            case "0", "false", "no", "paused", "stopped": false
            default: nil
            }
        default: nil
        }
    }
}

/// Event-driven Now Playing detector via distributed notifications (no MediaRemote).
@MainActor
@Observable
final class MusicPlaybackMonitor {
    static let shared = MusicPlaybackMonitor()

    /// True while at least one observed source reports Playing.
    private(set) var isPlaying = false

    #if DEBUG
    /// Settings → Development: pretend a player is playing (drives music-note overlay).
    var debugForcePlaying = false {
        didSet { recomputeIsPlaying() }
    }
    #endif

    private var playingSources: Set<String> = [] {
        didSet { recomputeIsPlaying() }
    }

    private var observerTokens: [NSObjectProtocol] = []
    private var terminateObserver: NSObjectProtocol?
    private var observedNames: Set<String> = []
    private var isStarted = false

    private init() {}

    private func recomputeIsPlaying() {
        #if DEBUG
        let next = debugForcePlaying || !playingSources.isEmpty
        #else
        let next = !playingSources.isEmpty
        #endif
        if next != isPlaying { isPlaying = next }
    }

    func start() {
        guard !isStarted else {
            reloadObservers()
            return
        }
        isStarted = true
        reloadObservers()
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            Task { @MainActor in
                MusicPlaybackMonitor.shared.handleAppTerminated(bundleID: bundleID)
            }
        }
    }

    func stop() {
        removeObservers()
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        playingSources.removeAll()
        #if DEBUG
        debugForcePlaying = false
        #endif
        isStarted = false
    }

    /// Re-subscribe using built-ins + custom names from settings.
    func reloadObservers() {
        guard isStarted else { return }
        let names = Self.resolvedNotificationNames(
            customRaw: AppSettings.shared.customMusicNotificationNames
        )
        guard names != observedNames else { return }
        removeObservers()
        observedNames = names
        // Drop sources whose notification is no longer observed.
        playingSources = playingSources.filter { names.contains($0) }

        let center = DistributedNotificationCenter.default()
        for name in names {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { notification in
                let playing = MusicPlaybackPayload.isPlaying(userInfo: notification.userInfo)
                Task { @MainActor in
                    MusicPlaybackMonitor.shared.applyPlayback(name: name, isPlaying: playing)
                }
            }
            observerTokens.append(token)
        }
    }

    static func resolvedNotificationNames(customRaw: String) -> Set<String> {
        var names = Set(BuiltInMusicNotification.allCases.map(\.notificationName))
        for line in customRaw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            names.insert(trimmed)
        }
        return names
    }

    private func applyPlayback(name: String, isPlaying playing: Bool) {
        if playing {
            playingSources.insert(name)
        } else {
            playingSources.remove(name)
        }
    }

    private func handleAppTerminated(bundleID: String?) {
        guard let bundleID else { return }

        for builtIn in BuiltInMusicNotification.allCases where builtIn.bundleIDs.contains(bundleID) {
            playingSources.remove(builtIn.notificationName)
        }
    }

    private func removeObservers() {
        let center = DistributedNotificationCenter.default()
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
        observedNames.removeAll()
    }
}
