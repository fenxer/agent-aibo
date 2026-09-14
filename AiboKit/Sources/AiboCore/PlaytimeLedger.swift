import Foundation

public struct PlaytimeRecord: Codable, Sendable, Equatable {
    public var id: String
    public var kind: AiboKind
    public var slug: String?
    public var displayName: String
    public var totalSeconds: Int
    public var updatedAtEpoch: Int64
    public var isOrphan: Bool

    public init(
        id: String,
        kind: AiboKind,
        slug: String? = nil,
        displayName: String,
        totalSeconds: Int = 0,
        updatedAtEpoch: Int64,
        isOrphan: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.slug = slug
        self.displayName = displayName
        self.totalSeconds = max(0, totalSeconds)
        self.updatedAtEpoch = updatedAtEpoch
        self.isOrphan = isOrphan
    }
}

public struct PlaytimeOpenSession: Codable, Sendable, Equatable {
    public var aiboID: String
    public var startedAtEpoch: Int64
}

public enum PlaytimeInstallDecision: Sendable, Equatable {
    case bindExisting(id: String)
    case ask(orphanID: String, displayName: String, totalSeconds: Int)
    case fresh
}

/// In-memory playtime book. Persistence and HMAC live in `PlaytimeCodec`.
public struct PlaytimeSnapshot: Codable, Sendable, Equatable {
    public var records: [PlaytimeRecord]
    public var openSession: PlaytimeOpenSession?

    public init(records: [PlaytimeRecord] = [], openSession: PlaytimeOpenSession? = nil) {
        self.records = records
        self.openSession = openSession
    }

    public static func epoch(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded())
    }

    public static func date(from epoch: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epoch))
    }

    public func record(id: String) -> PlaytimeRecord? {
        records.first { $0.id == id }
    }

    public func displayedSeconds(id: String, now: Date) -> Int {
        let total = record(id: id)?.totalSeconds ?? 0
        guard let session = openSession, session.aiboID == id else { return total }
        return total + elapsedSeconds(since: session.startedAtEpoch, now: now)
    }

    public func decision(for record: AiboLibraryRecord) -> PlaytimeInstallDecision {
        if records.contains(where: { $0.id == record.id }) {
            return .bindExisting(id: record.id)
        }
        if let slug = record.slug,
           let existing = records.first(where: { $0.slug == slug })
        {
            return .bindExisting(id: existing.id)
        }
        let matches = records.filter {
            $0.isOrphan && AiboLibraryNaming.displayNamesMatch($0.displayName, record.displayName)
        }
        if let orphan = matches.max(by: { $0.updatedAtEpoch < $1.updatedAtEpoch }) {
            return .ask(
                orphanID: orphan.id,
                displayName: orphan.displayName,
                totalSeconds: orphan.totalSeconds
            )
        }
        return .fresh
    }

    /// Crash / unclean shutdown: drop the open session without adding wall-clock time.
    public mutating func discardOpenSession() {
        openSession = nil
    }

    public mutating func ensureRecord(for libraryRecord: AiboLibraryRecord, now: Date) {
        let epoch = Self.epoch(from: now)
        if let index = records.firstIndex(where: { $0.id == libraryRecord.id }) {
            records[index].kind = libraryRecord.kind
            records[index].slug = libraryRecord.slug
            records[index].displayName = libraryRecord.displayName
            records[index].isOrphan = false
            records[index].updatedAtEpoch = epoch
            return
        }
        records.append(
            PlaytimeRecord(
                id: libraryRecord.id,
                kind: libraryRecord.kind,
                slug: libraryRecord.slug,
                displayName: libraryRecord.displayName,
                totalSeconds: 0,
                updatedAtEpoch: epoch
            )
        )
    }

    public mutating func bindExisting(from existingID: String, to libraryRecord: AiboLibraryRecord, now: Date) {
        let epoch = Self.epoch(from: now)
        guard let index = records.firstIndex(where: { $0.id == existingID }) else {
            ensureRecord(for: libraryRecord, now: now)
            return
        }
        if let collision = records.firstIndex(where: { $0.id == libraryRecord.id }), collision != index {
            records[index].totalSeconds += records[collision].totalSeconds
            records.remove(at: collision)
            guard let rebound = records.firstIndex(where: { $0.id == existingID }) else { return }
            applyLibraryIdentity(libraryRecord, at: rebound, epoch: epoch)
            return
        }
        applyLibraryIdentity(libraryRecord, at: index, epoch: epoch)
    }

    public mutating func adoptOrphan(orphanID: String, onto libraryRecord: AiboLibraryRecord, now: Date) {
        let orphanSeconds = record(id: orphanID)?.totalSeconds ?? 0
        records.removeAll { $0.id == orphanID }
        ensureRecord(for: libraryRecord, now: now)
        if let index = records.firstIndex(where: { $0.id == libraryRecord.id }) {
            records[index].totalSeconds += orphanSeconds
            records[index].isOrphan = false
            records[index].updatedAtEpoch = Self.epoch(from: now)
        }
    }

    public mutating func rename(id: String, to displayName: String, now: Date) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].displayName = displayName
        records[index].updatedAtEpoch = Self.epoch(from: now)
    }

    public mutating func markOrphans(ids: [String], now: Date) {
        let epoch = Self.epoch(from: now)
        let wanted = Set(ids)
        for index in records.indices where wanted.contains(records[index].id) {
            records[index].isOrphan = true
            records[index].updatedAtEpoch = epoch
        }
        if let session = openSession, wanted.contains(session.aiboID) {
            endSession(now: now)
        }
    }

    public mutating func beginSession(aiboID: String, now: Date) {
        openSession = PlaytimeOpenSession(aiboID: aiboID, startedAtEpoch: Self.epoch(from: now))
    }

    public mutating func endSession(now: Date) {
        guard let session = openSession else { return }
        let elapsed = elapsedSeconds(since: session.startedAtEpoch, now: now)
        if let index = records.firstIndex(where: { $0.id == session.aiboID }) {
            records[index].totalSeconds += elapsed
            records[index].updatedAtEpoch = Self.epoch(from: now)
        }
        openSession = nil
    }

    private mutating func applyLibraryIdentity(
        _ libraryRecord: AiboLibraryRecord,
        at index: Int,
        epoch: Int64
    ) {
        records[index].id = libraryRecord.id
        records[index].kind = libraryRecord.kind
        records[index].slug = libraryRecord.slug
        records[index].displayName = libraryRecord.displayName
        records[index].isOrphan = false
        records[index].updatedAtEpoch = epoch
    }

    private func elapsedSeconds(since startedAtEpoch: Int64, now: Date) -> Int {
        let nowEpoch = Self.epoch(from: now)
        guard nowEpoch > startedAtEpoch else { return 0 }
        return Int(nowEpoch - startedAtEpoch)
    }
}

/// Settings chip: under 24h → hours + minutes; 24h and up → days + hours.
public enum PlaytimeCompanionSpan: Sendable, Equatable {
    case hoursAndMinutes(hours: Int, minutes: Int)
    case daysAndHours(days: Int, hours: Int)

    public static func from(seconds: Int) -> PlaytimeCompanionSpan {
        let totalMinutes = max(0, seconds) / 60
        let totalHours = totalMinutes / 60
        if totalHours >= 24 {
            return .daysAndHours(days: totalHours / 24, hours: totalHours % 24)
        }
        return .hoursAndMinutes(hours: totalHours, minutes: totalMinutes % 60)
    }
}
