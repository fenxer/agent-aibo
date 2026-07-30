#if DEBUG
import AppKit
import Foundation

/// DEBUG-only listener for `NSDistributedNotificationCenter`.
///
/// Since macOS Catalina, `addObserver(forName: nil, …)` is privileged and
/// silently delivers nothing to normal apps. Discovery therefore means:
/// subscribe to **explicit** candidate names (built-ins, settings, or
/// `strings`-style scan of a player binary), then play/pause and see what fires.
@MainActor
@Observable
final class DistributedNotificationSniffer {
    static let shared = DistributedNotificationSniffer()

    struct Entry: Identifiable, Sendable {
        let id: UUID
        let date: Date
        let name: String
        let object: String?
        let userInfoSummary: String
    }

    /// One candidate notification name per line. All are subscribed while listening.
    var probeNamesRaw: String = DistributedNotificationSniffer.defaultProbeNames()

    /// Case-insensitive substring tokens (`|`), applied only to the on-screen log.
    var nameFilter = ""

    private(set) var isRunning = false
    private(set) var entries: [Entry] = []
    private(set) var capturedCount = 0
    private(set) var droppedByFilter = 0
    private(set) var subscribedCount = 0
    private(set) var lastScanSummary: String?

    private var observerTokens: [NSObjectProtocol] = []
    private let maxEntries = 300

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        subscribe(to: resolvedProbeNames())
    }

    func stop() {
        guard isRunning else { return }
        removeObservers()
        isRunning = false
        subscribedCount = 0
    }

    /// Re-subscribe after editing probe names while already listening.
    func reloadSubscriptions() {
        guard isRunning else { return }
        removeObservers()
        subscribe(to: resolvedProbeNames())
    }

    func clear() {
        entries.removeAll()
        capturedCount = 0
        droppedByFilter = 0
    }

    func copyLogToPasteboard() {
        let text = entries.reversed().map { entry in
            let time = Self.timeFormatter.string(from: entry.date)
            let objectPart = entry.object.map { " object=\($0)" } ?? ""
            let infoPart = entry.userInfoSummary.isEmpty ? "" : " \(entry.userInfoSummary)"
            return "[\(time)] \(entry.name)\(objectPart)\(infoPart)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func resetProbeNamesToDefaults() {
        probeNamesRaw = Self.defaultProbeNames()
        lastScanSummary = nil
        if isRunning { reloadSubscriptions() }
    }

    /// Pull reverse-DNS-looking strings from a player binary and merge into probe names.
    func scanExecutable(at path: URL) {
        do {
            let data = try Data(contentsOf: path, options: [.mappedIfSafe])
            let found = Self.candidateNotificationNames(in: data)
            let merged = resolvedProbeNames().union(found)
            probeNamesRaw = merged.sorted().joined(separator: "\n")
            lastScanSummary = "\(path.lastPathComponent): \(found.count) candidates (probe list now \(merged.count))"
            if isRunning { reloadSubscriptions() }
        } catch {
            lastScanSummary = "Scan failed: \(error.localizedDescription)"
        }
    }

    func scanNetEaseMusicIfPresent() {
        let path = URL(fileURLWithPath: "/Applications/NeteaseMusic.app/Contents/MacOS/NeteaseMusic")
        guard FileManager.default.isReadableFile(atPath: path.path) else {
            lastScanSummary = "NeteaseMusic.app not found at /Applications"
            return
        }
        scanExecutable(at: path)
    }

    private func resolvedProbeNames() -> Set<String> {
        var names = Set(
            probeNamesRaw
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        names.formUnion(BuiltInMusicNotification.allCases.map(\.notificationName))
        names.formUnion(
            MusicPlaybackMonitor.resolvedNotificationNames(
                customRaw: AppSettings.shared.customMusicNotificationNames
            )
        )
        return names
    }

    private func subscribe(to names: Set<String>) {
        let center = DistributedNotificationCenter.default()
        subscribedCount = names.count
        for name in names {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { notification in
                let noteName = notification.name.rawValue
                let object = notification.object.map { String(describing: $0) }
                let summary = Self.summarizeUserInfo(notification.userInfo)
                Task { @MainActor in
                    DistributedNotificationSniffer.shared.ingest(
                        name: noteName,
                        object: object,
                        userInfoSummary: summary
                    )
                }
            }
            observerTokens.append(token)
        }
    }

    private func removeObservers() {
        let center = DistributedNotificationCenter.default()
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    private func ingest(name: String, object: String?, userInfoSummary: String) {
        guard isRunning else { return }
        capturedCount += 1
        guard shouldKeep(name: name) else {
            droppedByFilter += 1
            return
        }

        entries.insert(
            Entry(
                id: UUID(),
                date: Date(),
                name: name,
                object: object,
                userInfoSummary: userInfoSummary
            ),
            at: 0
        )
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    private func shouldKeep(name: String) -> Bool {
        let tokens = nameFilter
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return true }
        let haystack = name.lowercased()
        return tokens.contains { haystack.contains($0) }
    }

    private static func defaultProbeNames() -> String {
        (
            BuiltInMusicNotification.allCases.map(\.notificationName)
                + [
                    // Common guesses / leftovers from NetEase binary strings (likely no-ops).
                    "com.netease.163music.playerInfo",
                    "com.netease.163music.PlaybackStateChanged",
                    "com.netease.cloudmusic.playerInfo",
                    "com.netease.cloudmusic.PlaybackStateChanged",
                    "com.netease.163music.playStateChanged",
                    "com.netease.cloudmusic.playStateChanged",
                ]
        )
        .sorted()
        .joined(separator: "\n")
    }

    /// ASCII `strings`-style scan for reverse-DNS tokens that might be notification names.
    nonisolated static func candidateNotificationNames(in data: Data) -> Set<String> {
        var result = Set<String>()
        var current = Data()
        current.reserveCapacity(128)

        func flush() {
            defer { current.removeAll(keepingCapacity: true) }
            guard current.count >= 12, current.count <= 120 else { return }
            guard let string = String(data: current, encoding: .ascii) else { return }
            guard string.hasPrefix("com.") || string.hasPrefix("org.") || string.hasPrefix("net.") else {
                return
            }
            let lowered = string.lowercased()
            let interesting =
                lowered.contains("player")
                || lowered.contains("playback")
                || lowered.contains("playing")
                || lowered.contains("music")
                || lowered.contains("itunes")
                || lowered.contains("spotify")
                || lowered.contains("netease")
                || lowered.contains("163music")
                || lowered.contains("cloudmusic")
                || lowered.contains("nowplaying")
                || lowered.contains("song")
                || lowered.contains("media")
            guard interesting else { return }
            guard string.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") })
            else { return }
            result.insert(string)
        }

        for byte in data {
            if byte >= 0x20 && byte <= 0x7E {
                current.append(byte)
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    private nonisolated static func summarizeUserInfo(_ userInfo: [AnyHashable: Any]?) -> String {
        guard let userInfo, !userInfo.isEmpty else { return "" }
        let parts = userInfo.keys.sorted { "\($0)" < "\($1)" }.map { key -> String in
            guard let value = userInfo[key] else { return "\(key)=nil" }
            let rendered: String
            switch value {
            case let string as String:
                rendered = truncate(string)
            case let number as NSNumber:
                rendered = number.stringValue
            case let date as Date:
                rendered = ISO8601DateFormatter().string(from: date)
            default:
                rendered = truncate(String(describing: value))
            }
            return "\(key)=\(rendered)"
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    private nonisolated static func truncate(_ string: String, limit: Int = 80) -> String {
        guard string.count > limit else { return string }
        return String(string.prefix(limit)) + "…"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
#endif
