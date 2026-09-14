import AiboCore
import AppKit
import Foundation

@MainActor
@Observable
final class PlaytimeStore {
    static let shared = PlaytimeStore()

    private static let currentAccount = "playtime.current"
    private static let lastGoodAccount = "playtime.lastGood"

    private(set) var snapshot = PlaytimeSnapshot()
    private(set) var daily = PlaytimeDailyBook()
    private let power = PlaytimePowerObserver()
    private var lastGoodPersistedAt: Date?
    private var didStart = false

    private init() {
        load()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        power.onPauseForSleepOrLid = { [weak self] in
            self?.handleSleepOrLidPause()
        }
        power.onResumeFromSleepOrLid = { [weak self] in
            self?.handleSleepOrLidResume()
        }
        power.onScreenLockChange = { [weak self] _ in
            self?.syncSession(persistLastGood: false)
        }
        power.start()
        syncSession(persistLastGood: false)
    }

    func displayedSeconds(id: String, now: Date = Date()) -> Int {
        snapshot.displayedSeconds(id: id, now: now)
    }

    func displayedDailySeconds(id: String, dayKey: String, now: Date = Date()) -> Int {
        daily.displayedSeconds(
            aiboID: id,
            dayKey: dayKey,
            openSession: snapshot.openSession,
            now: now,
            calendar: .current
        )
    }

    func displayedDayKeys(id: String, now: Date = Date()) -> [String] {
        daily.displayedDayKeys(
            aiboID: id,
            openSession: snapshot.openSession,
            now: now,
            calendar: .current
        )
    }

    func noteSelected() {
        syncSession(persistLastGood: false)
    }

    func noteRenamed(id: String, to displayName: String) {
        snapshot.rename(id: id, to: displayName, now: Date())
        persist(includingLastGood: false)
    }

    func noteRemoved(ids: [String]) {
        let now = Date()
        if let session = snapshot.openSession, ids.contains(session.aiboID) {
            closeOpenSession(now: now)
        }
        snapshot.markOrphans(ids: ids, now: now)
        persist(includingLastGood: false)
        syncSession(persistLastGood: false)
    }

    func noteInstalled(_ record: AiboLibraryRecord) {
        switch snapshot.decision(for: record) {
        case .bindExisting(let existingID):
            snapshot.bindExisting(from: existingID, to: record, now: Date())
            daily.rebind(from: existingID, to: record.id)
        case .ask(let orphanID, let displayName, let totalSeconds):
            presentAdoptAlert(
                record: record,
                orphanID: orphanID,
                displayName: displayName,
                totalSeconds: totalSeconds
            )
        case .fresh:
            snapshot.ensureRecord(for: record, now: Date())
        }
        persist(includingLastGood: false)
    }

    func noteVisibilityChanged() {
        syncSession(persistLastGood: false)
    }

    func flushForTermination() {
        closeOpenSession(now: Date())
        persist(includingLastGood: true)
    }

    private func handleSleepOrLidPause() {
        closeOpenSession(now: Date())
        persist(includingLastGood: true)
    }

    private func handleSleepOrLidResume() {
        if snapshot.openSession != nil {
            snapshot.discardOpenSession()
        }
        persist(includingLastGood: false)
        syncSession(persistLastGood: false)
    }

    private func syncSession(persistLastGood: Bool) {
        let now = Date()
        let selected = AiboLibraryStore.shared.selectedRecord
        if canAccumulate {
            if snapshot.openSession?.aiboID != selected.id {
                closeOpenSession(now: now)
                snapshot.ensureRecord(for: selected, now: now)
                snapshot.beginSession(aiboID: selected.id, now: now)
                persist(includingLastGood: persistLastGood)
            }
        } else if snapshot.openSession != nil {
            closeOpenSession(now: now)
            persist(includingLastGood: persistLastGood)
        }
    }

    private func closeOpenSession(now: Date) {
        guard let session = snapshot.endSession(now: now) else { return }
        daily.add(
            aiboID: session.aiboID,
            from: PlaytimeSnapshot.date(from: session.startedAtEpoch),
            to: now,
            calendar: .current
        )
    }

    private var canAccumulate: Bool {
        AiboPanelController.shared.isPlaytimeActiveSurface
            && !power.isLidClosed
            && !power.isScreenLocked
    }

    private func presentAdoptAlert(
        record: AiboLibraryRecord,
        orphanID: String,
        displayName: String,
        totalSeconds: Int
    ) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Continue Previous Time?")
        alert.informativeText = String(
            localized: "An aibo named “\(displayName)” already has recorded time (\(Self.alertDuration(totalSeconds))). Continue that time with this aibo, or start a new timer?"
        )
        alert.addButton(withTitle: String(localized: "Continue Time"))
        alert.addButton(withTitle: String(localized: "Start New Timer"))
        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn {
            snapshot.adoptOrphan(orphanID: orphanID, onto: record, now: Date())
            daily.rebind(from: orphanID, to: record.id)
        } else {
            snapshot.ensureRecord(for: record, now: Date())
        }
    }

    private static func alertDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    private func load() {
        loadSnapshot()
        loadDaily()
    }

    private func loadSnapshot() {
        if let data = KeychainStore.data(forAccount: Self.currentAccount),
           let loaded = PlaytimeCodec.decode(data)
        {
            snapshot = loaded
            snapshot.discardOpenSession()
            if KeychainStore.data(forAccount: Self.lastGoodAccount).flatMap(PlaytimeCodec.decode) != nil {
                lastGoodPersistedAt = Date()
            }
            return
        }
        if let backup = KeychainStore.data(forAccount: Self.lastGoodAccount),
           let loaded = PlaytimeCodec.decode(backup)
        {
            snapshot = loaded
            snapshot.discardOpenSession()
            try? KeychainStore.setData(backup, forAccount: Self.currentAccount)
            lastGoodPersistedAt = Date()
        }
    }

    private func loadDaily() {
        if let data = try? Data(contentsOf: AiboPaths.playtimeDailyURL),
           let loaded = PlaytimeDailyCodec.decode(data)
        {
            daily = loaded
            if (try? Data(contentsOf: AiboPaths.playtimeDailyLastGoodURL))
                .flatMap(PlaytimeDailyCodec.decode) != nil
            {
                lastGoodPersistedAt = lastGoodPersistedAt ?? Date()
            }
            return
        }
        if let backup = try? Data(contentsOf: AiboPaths.playtimeDailyLastGoodURL),
           let loaded = PlaytimeDailyCodec.decode(backup)
        {
            daily = loaded
            writeDailyFile(backup, to: AiboPaths.playtimeDailyURL)
            lastGoodPersistedAt = lastGoodPersistedAt ?? Date()
        }
    }

    private func persist(includingLastGood: Bool) {
        let refreshLastGood = includingLastGood || shouldRefreshLastGood()
        if let data = try? PlaytimeCodec.encode(snapshot) {
            try? KeychainStore.setData(data, forAccount: Self.currentAccount)
            if refreshLastGood {
                try? KeychainStore.setData(data, forAccount: Self.lastGoodAccount)
            }
        }
        if let data = try? PlaytimeDailyCodec.encode(daily) {
            writeDailyFile(data, to: AiboPaths.playtimeDailyURL)
            if refreshLastGood {
                writeDailyFile(data, to: AiboPaths.playtimeDailyLastGoodURL)
            }
        }
        if refreshLastGood {
            lastGoodPersistedAt = Date()
        }
    }

    private func writeDailyFile(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: AiboPaths.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Next persist retries. Do not rewrite last-good from a failed current write.
        }
    }

    private func shouldRefreshLastGood() -> Bool {
        guard let lastGoodPersistedAt else { return false }
        return !Calendar.current.isDate(lastGoodPersistedAt, inSameDayAs: Date())
    }
}
