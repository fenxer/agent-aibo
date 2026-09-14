import Foundation
import Testing
@testable import AiboCore

private func sampleRecord(
    id: String = "static.nova",
    kind: AiboKind = .staticImage,
    slug: String? = nil,
    name: String = "Nova"
) -> AiboLibraryRecord {
    AiboLibraryRecord(
        id: id,
        kind: kind,
        displayName: name,
        relativePath: "static/\(id)",
        slug: slug
    )
}

private func date(_ epoch: Int64) -> Date {
    PlaytimeSnapshot.date(from: epoch)
}

@Test func playtimeCodecRejectsTamperedSeconds() throws {
    var snapshot = PlaytimeSnapshot()
    snapshot.ensureRecord(for: sampleRecord(), now: date(1_000))
    snapshot.records[0].totalSeconds = 3600
    let data = try PlaytimeCodec.encode(snapshot)

    var envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var inner = envelope["snapshot"] as! [String: Any]
    var records = inner["records"] as! [[String: Any]]
    records[0]["totalSeconds"] = 99_999
    inner["records"] = records
    envelope["snapshot"] = inner
    let tampered = try JSONSerialization.data(withJSONObject: envelope)

    #expect(PlaytimeCodec.decode(tampered) == nil)
    #expect(PlaytimeCodec.decode(data)?.records.first?.totalSeconds == 3600)
}

@Test func playtimeCodecRoundTrip() throws {
    var snapshot = PlaytimeSnapshot()
    snapshot.ensureRecord(for: sampleRecord(slug: "nova"), now: date(50))
    snapshot.beginSession(aiboID: "static.nova", now: date(60))
    let data = try PlaytimeCodec.encode(snapshot)
    let decoded = try #require(PlaytimeCodec.decode(data))
    #expect(decoded == snapshot)
}

@Test func playtimeInstallMatchesIDThenSlugThenAsksName() {
    var snapshot = PlaytimeSnapshot()
    let now = date(100)
    snapshot.ensureRecord(for: sampleRecord(id: "petdex.boba", kind: .petdex, slug: "boba", name: "Boba"), now: now)
    snapshot.markOrphans(ids: ["petdex.boba"], now: now)

    #expect(
        snapshot.decision(for: sampleRecord(id: "petdex.boba", kind: .petdex, slug: "boba", name: "Boba"))
            == .bindExisting(id: "petdex.boba")
    )

    var renamed = sampleRecord(id: "petdex.boba", kind: .petdex, slug: "boba", name: "Boba")
    renamed.id = "petdex.other"
    #expect(snapshot.decision(for: renamed) == .bindExisting(id: "petdex.boba"))

    #expect(
        snapshot.decision(for: sampleRecord(id: "static.other", name: "Boba"))
            == .ask(orphanID: "petdex.boba", displayName: "Boba", totalSeconds: 0)
    )
    #expect(snapshot.decision(for: sampleRecord(id: "static.fresh", name: "Nova")) == .fresh)
}

@Test func playtimeAdoptOrphanAddsSecondsOntoNewIdentity() {
    var snapshot = PlaytimeSnapshot()
    let now = date(10)
    snapshot.ensureRecord(for: sampleRecord(id: "static.old", name: "Nova"), now: now)
    snapshot.records[0].totalSeconds = 1_200
    snapshot.markOrphans(ids: ["static.old"], now: now)

    let incoming = sampleRecord(id: "static.new", name: "Nova")
    snapshot.ensureRecord(for: incoming, now: date(20))
    snapshot.adoptOrphan(orphanID: "static.old", onto: incoming, now: date(21))

    #expect(snapshot.record(id: "static.old") == nil)
    #expect(snapshot.record(id: "static.new")?.totalSeconds == 1_200)
    #expect(snapshot.record(id: "static.new")?.isOrphan == false)
}

@Test func playtimeDiscardOpenSessionDoesNotAddTime() {
    var snapshot = PlaytimeSnapshot()
    snapshot.ensureRecord(for: sampleRecord(), now: date(0))
    snapshot.beginSession(aiboID: "static.nova", now: date(10))
    snapshot.discardOpenSession()
    #expect(snapshot.openSession == nil)
    #expect(snapshot.record(id: "static.nova")?.totalSeconds == 0)
    #expect(snapshot.displayedSeconds(id: "static.nova", now: date(10_000)) == 0)
}

@Test func playtimeEndSessionAddsElapsedAndIgnoresClockRollback() {
    var snapshot = PlaytimeSnapshot()
    snapshot.ensureRecord(for: sampleRecord(), now: date(0))
    snapshot.beginSession(aiboID: "static.nova", now: date(100))
    #expect(snapshot.displayedSeconds(id: "static.nova", now: date(160)) == 60)

    snapshot.endSession(now: date(160))
    #expect(snapshot.openSession == nil)
    #expect(snapshot.record(id: "static.nova")?.totalSeconds == 60)

    snapshot.beginSession(aiboID: "static.nova", now: date(200))
    snapshot.endSession(now: date(150))
    #expect(snapshot.record(id: "static.nova")?.totalSeconds == 60)
}

@Test func playtimeCompanionSpanSplitsAtTwentyFourHours() {
    #expect(PlaytimeCompanionSpan.from(seconds: 0) == .hoursAndMinutes(hours: 0, minutes: 0))
    #expect(PlaytimeCompanionSpan.from(seconds: 59) == .hoursAndMinutes(hours: 0, minutes: 0))
    #expect(PlaytimeCompanionSpan.from(seconds: 60) == .hoursAndMinutes(hours: 0, minutes: 1))
    #expect(PlaytimeCompanionSpan.from(seconds: 3 * 3600 + 12 * 60) == .hoursAndMinutes(hours: 3, minutes: 12))
    #expect(PlaytimeCompanionSpan.from(seconds: 24 * 3600 - 1) == .hoursAndMinutes(hours: 23, minutes: 59))
    #expect(PlaytimeCompanionSpan.from(seconds: 24 * 3600) == .daysAndHours(days: 1, hours: 0))
    #expect(PlaytimeCompanionSpan.from(seconds: 2 * 24 * 3600 + 5 * 3600) == .daysAndHours(days: 2, hours: 5))
}

@Test func playtimeDailySplitsAcrossLocalMidnight() {
    let calendar = utcPlusEightCalendar()
    let start = localDate(year: 2026, month: 9, day: 13, hour: 23, minute: 0, calendar: calendar)
    let end = localDate(year: 2026, month: 9, day: 14, hour: 1, minute: 0, calendar: calendar)
    let slices = PlaytimeDayAttribution.secondsByDay(from: start, to: end, calendar: calendar)
    #expect(slices["2026-09-13"] == 3600)
    #expect(slices["2026-09-14"] == 3600)
    #expect(slices.values.reduce(0, +) == 7200)
}

@Test func playtimeDailySameDayAndEmptyWindow() {
    let calendar = utcPlusEightCalendar()
    let start = localDate(year: 2026, month: 9, day: 14, hour: 10, minute: 0, calendar: calendar)
    let end = localDate(year: 2026, month: 9, day: 14, hour: 10, minute: 5, calendar: calendar)
    #expect(PlaytimeDayAttribution.secondsByDay(from: start, to: end, calendar: calendar) == ["2026-09-14": 300])
    #expect(PlaytimeDayAttribution.secondsByDay(from: end, to: start, calendar: calendar).isEmpty)
}

@Test func playtimeDailyBookRebindMergesAndShowsLiveToday() {
    let calendar = utcPlusEightCalendar()
    var book = PlaytimeDailyBook()
    let start = localDate(year: 2026, month: 9, day: 13, hour: 22, minute: 0, calendar: calendar)
    let end = localDate(year: 2026, month: 9, day: 13, hour: 23, minute: 0, calendar: calendar)
    book.add(aiboID: "static.old", from: start, to: end, calendar: calendar)
    book.add(aiboID: "static.new", from: start, to: end, calendar: calendar)
    book.rebind(from: "static.old", to: "static.new")
    #expect(book.seconds(aiboID: "static.old", dayKey: "2026-09-13") == 0)
    #expect(book.seconds(aiboID: "static.new", dayKey: "2026-09-13") == 7200)

    let sessionStart = localDate(year: 2026, month: 9, day: 14, hour: 8, minute: 0, calendar: calendar)
    let now = localDate(year: 2026, month: 9, day: 14, hour: 8, minute: 10, calendar: calendar)
    let session = PlaytimeOpenSession(
        aiboID: "static.new",
        startedAtEpoch: PlaytimeSnapshot.epoch(from: sessionStart)
    )
    #expect(book.displayedDayKeys(aiboID: "static.new", openSession: session, now: now, calendar: calendar) == [
        "2026-09-14",
        "2026-09-13",
    ])
    #expect(book.displayedSeconds(aiboID: "static.new", dayKey: "2026-09-14", openSession: session, now: now, calendar: calendar) == 600)
}

@Test func playtimeDailyCodecRejectsTamperedSeconds() throws {
    var book = PlaytimeDailyBook()
    book.daysByAiboID = ["static.nova": ["2026-09-14": 120]]
    let data = try PlaytimeDailyCodec.encode(book)

    var envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var inner = envelope["book"] as! [String: Any]
    var days = inner["daysByAiboID"] as! [String: [String: Any]]
    var nova = days["static.nova"] ?? [:]
    nova["2026-09-14"] = 99_999
    days["static.nova"] = nova
    inner["daysByAiboID"] = days
    envelope["book"] = inner
    let tampered = try JSONSerialization.data(withJSONObject: envelope)

    #expect(PlaytimeDailyCodec.decode(tampered) == nil)
    #expect(PlaytimeDailyCodec.decode(data)?.seconds(aiboID: "static.nova", dayKey: "2026-09-14") == 120)
}

@Test func playtimeBindExistingRewritesOpenSessionID() {
    var snapshot = PlaytimeSnapshot()
    let now = date(100)
    snapshot.ensureRecord(for: sampleRecord(id: "petdex.boba", kind: .petdex, slug: "boba", name: "Boba"), now: now)
    snapshot.beginSession(aiboID: "petdex.boba", now: date(110))
    let incoming = sampleRecord(id: "petdex.other", kind: .petdex, slug: "boba", name: "Boba")
    snapshot.bindExisting(from: "petdex.boba", to: incoming, now: date(120))
    #expect(snapshot.openSession?.aiboID == "petdex.other")
    #expect(snapshot.record(id: "petdex.boba") == nil)
    #expect(snapshot.record(id: "petdex.other") != nil)
}

@Test func playtimeRenameAndOrphanKeepIdentity() {
    var snapshot = PlaytimeSnapshot()
    snapshot.ensureRecord(for: sampleRecord(), now: date(1))
    snapshot.rename(id: "static.nova", to: "Home", now: date(2))
    #expect(snapshot.record(id: "static.nova")?.displayName == "Home")

    snapshot.markOrphans(ids: ["static.nova"], now: date(3))
    #expect(snapshot.record(id: "static.nova")?.isOrphan == true)
    #expect(snapshot.record(id: "static.nova")?.id == "static.nova")
}

private func utcPlusEightCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func localDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    calendar: Calendar
) -> Date {
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = hour
    parts.minute = minute
    parts.second = 0
    return calendar.date(from: parts)!
}
