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

@Test func playtimeRenameAndOrphanKeepIdentity() {
    var snapshot = PlaytimeSnapshot()
    snapshot.ensureRecord(for: sampleRecord(), now: date(1))
    snapshot.rename(id: "static.nova", to: "Home", now: date(2))
    #expect(snapshot.record(id: "static.nova")?.displayName == "Home")

    snapshot.markOrphans(ids: ["static.nova"], now: date(3))
    #expect(snapshot.record(id: "static.nova")?.isOrphan == true)
    #expect(snapshot.record(id: "static.nova")?.id == "static.nova")
}
