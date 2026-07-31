import AppKit
import Foundation
import MediaRemoteAdapter

/// Built-in players that post well-known `NSDistributedNotificationCenter` names.
/// Kept as a fallback when MediaRemote adapter is unavailable; NetEase etc. still need Now Playing.
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

/// Event-driven Now Playing detector:
/// 1. System Now Playing via MediaRemoteAdapter (covers NetEase / QQ / browser, …)
/// 2. Distributed notifications for Music / Spotify as a lightweight fallback
@MainActor
@Observable
final class MusicPlaybackMonitor {
    static let shared = MusicPlaybackMonitor()

    private static let mediaRemoteSourceID = "mediaRemote"

    /// True while at least one observed source reports Playing.
    private(set) var isPlaying = false

    #if DEBUG
    /// Settings → Development: pretend a player is playing (drives music-note overlay).
    var debugForcePlaying = false {
        didSet { recomputeIsPlaying() }
    }

    /// Latest MediaRemoteAdapter payload dump (artwork bytes omitted).
    private(set) var debugLastMediaRemoteDump = "(no update yet)"
    private(set) var debugMediaRemoteUpdateCount = 0
    #endif

    private var playingSources: Set<String> = [] {
        didSet { recomputeIsPlaying() }
    }

    private var observerTokens: [NSObjectProtocol] = []
    private var terminateObserver: NSObjectProtocol?
    private var observedNames: Set<String> = []
    private var isStarted = false

    private var mediaController: MediaController?

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
            startMediaRemoteIfNeeded()
            return
        }
        isStarted = true
        reloadObservers()
        startMediaRemoteIfNeeded()
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
        stopMediaRemote()
        removeObservers()
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        playingSources.removeAll()
        #if DEBUG
        debugForcePlaying = false
        debugLastMediaRemoteDump = "(stopped)"
        debugMediaRemoteUpdateCount = 0
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
        // Drop notification sources whose name is no longer observed; keep MediaRemote.
        playingSources = playingSources.filter {
            $0 == Self.mediaRemoteSourceID || names.contains($0)
        }

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

    private func startMediaRemoteIfNeeded() {
        guard isStarted, mediaController == nil else { return }

        let controller = MediaController()
        controller.onTrackInfoReceived = { trackInfo in
            let playing = Self.isPlaying(trackInfo: trackInfo)
            Task { @MainActor in
                let monitor = MusicPlaybackMonitor.shared
                let changed = monitor.applyPlayback(
                    name: Self.mediaRemoteSourceID,
                    isPlaying: playing
                )
                #if DEBUG
                // Stream payloads are isPlaying-only; refresh dump on edges.
                if changed {
                    monitor.recordDebugMediaRemote(trackInfo)
                }
                #endif
            }
        }
        controller.onListenerTerminated = {
            Task { @MainActor in
                #if DEBUG
                MusicPlaybackMonitor.shared.debugLastMediaRemoteDump = "(listener terminated)"
                #endif
                MusicPlaybackMonitor.shared.applyPlayback(
                    name: Self.mediaRemoteSourceID,
                    isPlaying: false
                )
                // Drop the dead controller so a later start() can recreate it.
                MusicPlaybackMonitor.shared.mediaController = nil
            }
        }
        mediaController = controller
        controller.startListening()
    }

    private func stopMediaRemote() {
        mediaController?.stopListening()
        mediaController = nil
        playingSources.remove(Self.mediaRemoteSourceID)
    }

    #if DEBUG
    /// One-shot fetch for Development pane (does not require stream restart).
    func debugFetchMediaRemoteOnce() {
        let controller = mediaController ?? MediaController()
        controller.getTrackInfo { trackInfo in
            Task { @MainActor in
                MusicPlaybackMonitor.shared.recordDebugMediaRemote(trackInfo)
            }
        }
    }

    private func recordDebugMediaRemote(_ trackInfo: TrackInfo?) {
        debugMediaRemoteUpdateCount += 1
        debugLastMediaRemoteDump = Self.formatDebugMediaRemote(trackInfo)
    }

    private nonisolated static func formatDebugMediaRemote(_ trackInfo: TrackInfo?) -> String {
        let stamp = Self.debugTimeFormatter.string(from: Date())
        guard let payload = trackInfo?.payload else {
            return "[\(stamp)] nil (no now-playing item)"
        }

        var lines: [String] = ["[\(stamp)]"]
        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("\(key): \(value)")
        }
        func addAny<T>(_ key: String, _ value: T?) {
            guard let value else { return }
            lines.append("\(key): \(value)")
        }

        add("title", payload.title)
        add("artist", payload.artist)
        add("album", payload.album)
        addAny("isPlaying", payload.isPlaying)
        addAny("playbackRate", payload.playbackRate)
        add("applicationName", payload.applicationName)
        add("bundleIdentifier", payload.bundleIdentifier)
        addAny("PID", payload.PID.map(Int.init))
        if let micros = payload.durationMicros {
            lines.append(String(format: "duration: %.3fs", micros / 1_000_000))
        }
        if let micros = payload.elapsedTimeMicros {
            lines.append(String(format: "elapsed: %.3fs", micros / 1_000_000))
        }
        if let live = payload.currentElapsedTime {
            lines.append(String(format: "elapsedNow: %.3fs", live))
        }
        addAny("shuffleMode", payload.shuffleMode.map { "\($0)" })
        addAny("repeatMode", payload.repeatMode.map { "\($0)" })
        addAny("timestampEpochMicros", payload.timestampEpochMicros)
        if let mime = payload.artworkMimeType {
            let bytes = payload.artworkDataBase64?.count ?? 0
            lines.append("artwork: \(mime), base64Chars=\(bytes) (omitted)")
        } else if payload.artwork != nil {
            lines.append("artwork: present (decoded, base64 omitted)")
        }

        return lines.joined(separator: "\n")
    }

    private static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    #endif

    private nonisolated static func isPlaying(trackInfo: TrackInfo?) -> Bool {
        guard let payload = trackInfo?.payload else { return false }
        if let playing = payload.isPlaying { return playing }
        if let rate = payload.playbackRate { return rate > 0 }
        return false
    }

    /// Returns whether `playingSources` actually changed.
    @discardableResult
    private func applyPlayback(name: String, isPlaying playing: Bool) -> Bool {
        if playing {
            guard !playingSources.contains(name) else { return false }
            playingSources.insert(name)
            return true
        }
        guard playingSources.contains(name) else { return false }
        playingSources.remove(name)
        return true
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
