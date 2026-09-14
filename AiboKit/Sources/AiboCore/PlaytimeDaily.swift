import Foundation

/// Local-calendar day keys (`yyyy-MM-dd`) and per-aibo second totals.
public struct PlaytimeDailyBook: Codable, Sendable, Equatable {
    public var daysByAiboID: [String: [String: Int]]

    public init(daysByAiboID: [String: [String: Int]] = [:]) {
        self.daysByAiboID = daysByAiboID
    }

    public mutating func add(aiboID: String, from start: Date, to end: Date, calendar: Calendar) {
        let slices = PlaytimeDayAttribution.secondsByDay(from: start, to: end, calendar: calendar)
        guard !slices.isEmpty else { return }
        var days = daysByAiboID[aiboID] ?? [:]
        for (day, seconds) in slices {
            days[day, default: 0] += seconds
        }
        daysByAiboID[aiboID] = days
    }

    public mutating func rebind(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let moving = daysByAiboID.removeValue(forKey: oldID) ?? [:]
        guard !moving.isEmpty else { return }
        var dest = daysByAiboID[newID] ?? [:]
        for (day, seconds) in moving {
            dest[day, default: 0] += seconds
        }
        daysByAiboID[newID] = dest
    }

    public func seconds(aiboID: String, dayKey: String) -> Int {
        daysByAiboID[aiboID]?[dayKey] ?? 0
    }

    public func displayedSeconds(
        aiboID: String,
        dayKey: String,
        openSession: PlaytimeOpenSession?,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let stored = seconds(aiboID: aiboID, dayKey: dayKey)
        guard let session = openSession, session.aiboID == aiboID else { return stored }
        let live = PlaytimeDayAttribution.secondsByDay(
            from: PlaytimeSnapshot.date(from: session.startedAtEpoch),
            to: now,
            calendar: calendar
        )[dayKey] ?? 0
        return stored + live
    }

    public func displayedDayKeys(
        aiboID: String,
        openSession: PlaytimeOpenSession?,
        now: Date,
        calendar: Calendar
    ) -> [String] {
        var keys = Set((daysByAiboID[aiboID] ?? [:]).keys)
        if let session = openSession, session.aiboID == aiboID {
            let live = PlaytimeDayAttribution.secondsByDay(
                from: PlaytimeSnapshot.date(from: session.startedAtEpoch),
                to: now,
                calendar: calendar
            )
            keys.formUnion(live.keys)
        }
        return keys.sorted(by: >)
    }
}

public enum PlaytimeDayAttribution: Sendable {
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Splits `[start, end)` across local calendar midnights. No timer — call at session edges.
    public static func secondsByDay(from start: Date, to end: Date, calendar: Calendar) -> [String: Int] {
        let startDate = PlaytimeSnapshot.date(from: PlaytimeSnapshot.epoch(from: start))
        let endDate = PlaytimeSnapshot.date(from: PlaytimeSnapshot.epoch(from: end))
        guard endDate > startDate else { return [:] }
        var result: [String: Int] = [:]
        var cursor = startDate
        var steps = 0
        while cursor < endDate, steps < 4_000 {
            steps += 1
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let sliceEnd = min(endDate, nextDay)
            let seconds = Int(PlaytimeSnapshot.epoch(from: sliceEnd) - PlaytimeSnapshot.epoch(from: cursor))
            if seconds > 0 {
                result[dayKey(for: cursor, calendar: calendar), default: 0] += seconds
            }
            cursor = sliceEnd
        }
        if cursor < endDate {
            let leftover = Int(PlaytimeSnapshot.epoch(from: endDate) - PlaytimeSnapshot.epoch(from: cursor))
            if leftover > 0 {
                result[dayKey(for: cursor, calendar: calendar), default: 0] += leftover
            }
        }
        return result
    }
}
