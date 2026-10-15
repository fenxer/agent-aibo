import Foundation
import Testing
@testable import AiboCore

private func record(
    id: String,
    kind: AiboKind = .staticImage,
    slug: String? = nil,
    name: String,
    seconds: Int = 0,
    orphan: Bool = false
) -> PlaytimeRecord {
    PlaytimeRecord(
        id: id,
        kind: kind,
        slug: slug,
        displayName: name,
        totalSeconds: seconds,
        updatedAtEpoch: 10,
        isOrphan: orphan
    )
}

private func settingsFixture() -> AiboBackupSettings {
    AiboBackupSettings(
        themeMode: "dark",
        languageMode: "english",
        bubbleGlassStyle: "clear",
        bubbleGlassTint: nil,
        cursorBubbleGlassStyle: "regular",
        codexBubbleGlassStyle: "clear",
        deepseekBubbleGlassStyle: "identity",
        cursorBubbleGlassTint: AiboBackupColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
        codexBubbleGlassTint: nil,
        deepseekBubbleGlassTint: nil,
        cursorCapsuleColor: nil,
        codexCapsuleColor: nil,
        deepseekCapsuleColor: nil,
        codexPlanProgressShaderEnabled: true,
        codexPlanProgressShaderPrimary: nil,
        deepseekPlanProgressShaderEnabled: false,
        deepseekPlanProgressShaderPrimary: nil,
        restoreLastAiboPosition: true,
        hideWhenFullscreen: true,
        disableMouseTracking: false,
        mouseShakeDodgeEnabled: true,
        centerXPercent: 0.25,
        centerYPercent: 0.75,
        musicNotesEnabled: true,
        musicNotesColorMode: "aiboAccent",
        musicNotesCustomColor: AiboBackupColor(red: 1, green: 0, blue: 0.5, alpha: 1),
        customMusicNotificationNames: "",
        webhookEnabled: false,
        webhookPort: 8787,
        webhookDismissMode: "onClick",
        webhookAutoDismissSeconds: 12,
        publicWebhookURL: "",
        hookSprites: HookSpriteMappingFile(cursor: ["stop": "waving"]),
        actionSprites: ["drag-left": "running-left"]
    )
}

@Test func backupSuggestedFileNameUsesLocalYearMonthDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
    #expect(
        AiboBackupArchive.suggestedFileName(on: date, calendar: calendar)
            == "aibo-backup-261014.aiboarchive"
    )
}

@Test func backupAddSumsTheSameDayAndRebuildsLifetime() {
    let local = AiboBackupPlaytimeFile(
        records: [record(id: "builtin.default", kind: .builtInDefault, name: "Poli", seconds: 9_999)],
        daysByAiboID: ["builtin.default": ["2026-10-14": 3_600]]
    )
    let incoming = AiboBackupPlaytimeFile(
        records: [record(id: "builtin.default", kind: .builtInDefault, name: "Poli", seconds: 100)],
        daysByAiboID: ["builtin.default": ["2026-10-14": 1_800, "2026-10-13": 600]]
    )
    let merged = AiboBackupPlaytimeMerge.merge(
        local: local,
        incoming: incoming,
        mode: .add,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(merged.daysByAiboID["builtin.default"]?["2026-10-14"] == 5_400)
    #expect(merged.daysByAiboID["builtin.default"]?["2026-10-13"] == 600)
    #expect(merged.records.count == 1)
    #expect(merged.records[0].totalSeconds == 6_000)
    #expect(merged.records[0].isOrphan == false)
}

@Test func backupAddRebindsPetdexBySlug() {
    let local = AiboBackupPlaytimeFile(
        records: [record(id: "petdex.old", kind: .petdex, slug: "boba", name: "Boba", seconds: 50)],
        daysByAiboID: ["petdex.old": ["2026-10-01": 50]]
    )
    let incoming = AiboBackupPlaytimeFile(
        records: [record(id: "petdex.boba", kind: .petdex, slug: "boba", name: "Boba")],
        daysByAiboID: ["petdex.boba": ["2026-10-02": 10]]
    )
    let merged = AiboBackupPlaytimeMerge.merge(
        local: local,
        incoming: incoming,
        mode: .add,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(merged.records.map(\.id) == ["petdex.boba"])
    #expect(merged.daysByAiboID["petdex.old"] == nil)
    #expect(merged.daysByAiboID["petdex.boba"] == ["2026-10-02": 10, "2026-10-01": 50])
    #expect(merged.records[0].totalSeconds == 60)
}

@Test func backupAddKeepsUnmatchedLocalTimeAsOrphan() {
    let local = AiboBackupPlaytimeFile(
        records: [record(id: "static.mine", name: "Nova", seconds: 20)],
        daysByAiboID: ["static.mine": ["2026-10-01": 20]]
    )
    let incoming = AiboBackupPlaytimeFile(
        records: [record(id: "static.other", name: "Miso")],
        daysByAiboID: [:]
    )
    let merged = AiboBackupPlaytimeMerge.merge(
        local: local,
        incoming: incoming,
        mode: .add,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let orphan = merged.records.first { $0.id == "static.mine" }
    #expect(orphan?.isOrphan == true)
    #expect(orphan?.totalSeconds == 20)
    #expect(merged.daysByAiboID["static.mine"]?["2026-10-01"] == 20)
}

@Test func backupAddMatchesStaticImagesByDisplayName() {
    let local = AiboBackupPlaytimeFile(
        records: [record(id: "static.local", name: "Nova")],
        daysByAiboID: ["static.local": ["2026-10-01": 15]]
    )
    let incoming = AiboBackupPlaytimeFile(
        records: [record(id: "static.backup", name: "nova")],
        daysByAiboID: ["static.backup": ["2026-10-01": 5]]
    )
    let merged = AiboBackupPlaytimeMerge.merge(
        local: local,
        incoming: incoming,
        mode: .add,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(merged.records.map(\.id) == ["static.backup"])
    #expect(merged.daysByAiboID["static.backup"]?["2026-10-01"] == 20)
    #expect(merged.records[0].totalSeconds == 20)
}

@Test func backupAddDoesNotGiveBuiltInTimeToAPetWithTheSameName() {
    let local = AiboBackupPlaytimeFile(
        records: [record(id: "builtin.default", kind: .builtInDefault, name: "Poli", seconds: 30)],
        daysByAiboID: ["builtin.default": ["2026-10-01": 30]]
    )
    let incoming = AiboBackupPlaytimeFile(
        records: [record(id: "petdex.poli", kind: .petdex, slug: "poli", name: "Poli")],
        daysByAiboID: [:]
    )
    let merged = AiboBackupPlaytimeMerge.merge(
        local: local,
        incoming: incoming,
        mode: .add,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(merged.daysByAiboID["petdex.poli"] == nil)
    #expect(merged.records.contains { $0.id == "builtin.default" && $0.isOrphan && $0.totalSeconds == 30 })
    #expect(merged.records.first { $0.id == "petdex.poli" }?.totalSeconds == 0)
}

@Test func backupReplaceKeepsTheIncomingLedger() {
    let local = AiboBackupPlaytimeFile(
        records: [record(id: "builtin.default", kind: .builtInDefault, name: "Poli", seconds: 10)],
        daysByAiboID: ["builtin.default": ["2026-10-01": 10]]
    )
    let incoming = AiboBackupPlaytimeFile(
        records: [record(id: "builtin.default", kind: .builtInDefault, name: "Poli", seconds: 100)],
        daysByAiboID: [:]
    )
    let merged = AiboBackupPlaytimeMerge.merge(
        local: local,
        incoming: incoming,
        mode: .replace,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(merged.records[0].totalSeconds == 100)
    #expect(merged.daysByAiboID.isEmpty)
}

@Test func backupArchiveRoundTripsLibrarySettingsAndPlaytime() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-backup-test-\(UUID().uuidString)", isDirectory: true)
    let aibos = root.appendingPathComponent("aibos", isDirectory: true)
    try FileManager.default.createDirectory(at: aibos, withIntermediateDirectories: true)
    let library = AiboLibraryFile(
        selectedID: "static.nova",
        records: [
            AiboLibraryRecord(
                id: "static.nova",
                kind: .staticImage,
                displayName: "Nova",
                relativePath: "static/nova.png"
            ),
        ]
    )
    try AiboLibraryCodec.encode(library).write(to: aibos.appendingPathComponent("library.json"))
    try FileManager.default.createDirectory(
        at: aibos.appendingPathComponent("static", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("png".utf8).write(to: aibos.appendingPathComponent("static/nova.png"))

    let archive = root.appendingPathComponent("Aibo.aiboarchive")
    let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let playtime = AiboBackupPlaytimeFile(
        records: [record(id: "static.nova", name: "Nova", seconds: 12)],
        daysByAiboID: ["static.nova": ["2026-10-14": 12]]
    )
    try AiboBackupArchive.write(
        settings: settingsFixture(),
        playtime: playtime,
        aibosSource: aibos,
        appVersion: "1.2.3",
        exportedAt: exportedAt,
        to: archive
    )

    let extracted = root.appendingPathComponent("out", isDirectory: true)
    let document = try AiboBackupArchive.read(archive: archive, into: extracted)
    #expect(document.manifest.formatVersion == 1)
    #expect(document.manifest.appVersion == "1.2.3")
    #expect(document.manifest.exportedAt == exportedAt)
    #expect(document.settings == settingsFixture())
    #expect(document.playtime == playtime)
    let libraryData = try Data(contentsOf: document.aibosDirectory.appendingPathComponent("library.json"))
    #expect(try AiboLibraryCodec.decode(libraryData).selectedID == "static.nova")
    #expect(FileManager.default.fileExists(atPath: document.aibosDirectory.appendingPathComponent("static/nova.png").path))
    try? FileManager.default.removeItem(at: root)
}

@Test func backupArchiveRejectsANewerFormat() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-backup-new-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let aibos = root.appendingPathComponent("aibos", isDirectory: true)
    try FileManager.default.createDirectory(at: aibos, withIntermediateDirectories: true)
    let archive = root.appendingPathComponent("Aibo.aiboarchive")
    try AiboBackupArchive.write(
        settings: settingsFixture(),
        playtime: AiboBackupPlaytimeFile(records: [], daysByAiboID: [:]),
        aibosSource: aibos,
        appVersion: "1",
        to: archive
    )
    let extracted = root.appendingPathComponent("edit", isDirectory: true)
    _ = try AiboBackupArchive.read(archive: archive, into: extracted)
    let manifestURL = extracted.appendingPathComponent("manifest.json")
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    object["formatVersion"] = 2
    try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)
    let repacked = root.appendingPathComponent("newer.aiboarchive")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--norsrc", extracted.path, repacked.path]
    try process.run()
    process.waitUntilExit()
    let destination = root.appendingPathComponent("newer-out", isDirectory: true)
    #expect(throws: AiboBackupError.unsupportedFormat) {
        try AiboBackupArchive.read(archive: repacked, into: destination)
    }
}

@Test func backupArchiveRejectsASymlinkInTheLibrary() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-backup-link-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let aibos = root.appendingPathComponent("aibos", isDirectory: true)
    try FileManager.default.createDirectory(at: aibos, withIntermediateDirectories: true)
    let outside = root.appendingPathComponent("secret.txt")
    try Data("nope".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(
        at: aibos.appendingPathComponent("secret.txt"),
        withDestinationURL: outside
    )
    #expect(throws: AiboBackupError.unsafePath) {
        try AiboBackupArchive.write(
            settings: settingsFixture(),
            playtime: AiboBackupPlaytimeFile(records: [], daysByAiboID: [:]),
            aibosSource: aibos,
            appVersion: "1",
            to: root.appendingPathComponent("Aibo.aiboarchive")
        )
    }
}

@Test func backupLibraryReplacementRestoresThePreviousTree() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-backup-swap-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("aibos", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let previous = AiboLibraryFile(
        selectedID: "static.old",
        records: [
            AiboLibraryRecord(
                id: "static.old",
                kind: .staticImage,
                displayName: "Old",
                relativePath: "static/old.png"
            ),
        ]
    )
    try AiboLibraryCodec.encode(previous).write(to: destination.appendingPathComponent("library.json"))
    let source = root.appendingPathComponent("incoming", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let library = AiboLibraryFile(selectedID: AiboLibraryDefaults.builtInID)
    try AiboLibraryCodec.encode(library).write(to: source.appendingPathComponent("library.json"))

    var replacement = try AiboBackupArchive.replaceLibrary(at: destination, with: source)
    let installed = try AiboLibraryCodec.decode(
        Data(contentsOf: destination.appendingPathComponent("library.json"))
    )
    #expect(installed.selectedID == AiboLibraryDefaults.builtInID)
    try replacement.restore()
    let restored = try AiboLibraryCodec.decode(
        Data(contentsOf: destination.appendingPathComponent("library.json"))
    )
    #expect(restored.selectedID == "static.old")
}
