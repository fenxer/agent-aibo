import Foundation
import Testing
@testable import AiboCore

@Test func petdexSlugParserAcceptsBareSlug() {
    #expect(PetdexSlugParser.parse("boba") == "boba")
    #expect(PetdexSlugParser.isValidSlug("homelander") == true)
    #expect(PetdexSlugParser.isValidSlug("Boba") == false)
    #expect(PetdexSlugParser.isValidSlug("-bad") == false)
}

@Test func petdexSlugParserExtractsFromURLs() {
    #expect(PetdexSlugParser.parse("https://petdex.dev/pets/boba") == "boba")
    #expect(PetdexSlugParser.parse("https://petdex.dev/en/pets/homelander") == "homelander")
    #expect(PetdexSlugParser.parse("https://petdex.dev/api/install-pet/boba") == "boba")
    #expect(PetdexSlugParser.parse("https://petdex.dev/install/kebo") == "kebo")
    #expect(PetdexSlugParser.parse("not a url!!!") == nil)
}

@Test func petdexInstallAPIDecodesSuccess() throws {
    let json = """
    {"ok":true,"pet":{"slug":"boba","displayName":"Boba","petJsonUrl":"https://assets.petdex.dev/curated/boba/petjson-v2.json","spritesheetUrl":"https://assets.petdex.dev/curated/boba/sprite-v2.webp","spriteExt":"webp"}}
    """
    let response = try PetdexInstallAPI.decodeResponse(Data(json.utf8))
    #expect(response.ok)
    #expect(response.pet?.slug == "boba")
    #expect(response.pet?.spriteExt == "webp")

    let record = PetdexInstallAPI.makeRecord(
        installable: response.pet!,
        petJSON: PetdexPetJSON(id: "boba", displayName: "Boba", spriteVersionNumber: 2)
    )
    #expect(record.id == "petdex.boba")
    #expect(record.kind == .petdex)
    #expect(record.spriteFileName == "spritesheet.webp")
    #expect(record.spriteVersionNumber == 2)
    #expect(record.installSource == "https://petdex.dev/pets/boba")
    #expect(record.installedAt != nil)
}

@Test func aiboLibrarySnapshotIncludesBuiltInAndFixesSelection() throws {
    let file = AiboLibraryFile(
        selectedID: "missing",
        records: [
            AiboLibraryRecord(
                id: "petdex.boba",
                kind: .petdex,
                displayName: "Boba",
                relativePath: "petdex/boba",
                slug: "boba",
                spriteFileName: "spritesheet.webp"
            ),
        ]
    )
    let snap = AiboLibraryCodec.snapshot(from: file)
    #expect(snap.selectedID == AiboLibraryDefaults.builtInID)
    #expect(snap.records.first?.id == AiboLibraryDefaults.builtInID)
    #expect(snap.records.contains(where: { $0.id == "petdex.boba" }))

    let roundTrip = try AiboLibraryCodec.decode(AiboLibraryCodec.encode(file))
    #expect(roundTrip.records.count == 1)
}

@Test func aiboLibraryNamingTrimsAndRejectsEmpty() {
    #expect(AiboLibraryNaming.normalizedDisplayName("  Boba  ") == "Boba")
    #expect(AiboLibraryNaming.normalizedDisplayName("   ") == nil)
    #expect(AiboLibraryNaming.normalizedDisplayName("") == nil)
}

@Test func aiboLibrarySnapshotAppliesRenamedBuiltIn() {
    var builtIn = AiboLibraryRecord.builtInDefault
    builtIn.displayName = "Home"
    let file = AiboLibraryFile(
        selectedID: AiboLibraryDefaults.builtInID,
        records: [builtIn]
    )
    let snap = AiboLibraryCodec.snapshot(from: file)
    #expect(snap.records.first?.displayName == "Home")
    #expect(snap.records.first?.id == AiboLibraryDefaults.builtInID)
}

@Test func aiboLibraryPersistableRecordsKeepsRenamedBuiltInOnly() {
    var builtIn = AiboLibraryRecord.builtInDefault
    builtIn.displayName = "Home"
    let boba = AiboLibraryRecord(
        id: "petdex.boba",
        kind: .petdex,
        displayName: "Boba",
        relativePath: "petdex/boba"
    )

    let renamed = AiboLibraryCodec.persistableRecords(from: [builtIn, boba])
    #expect(renamed.map(\.id) == [AiboLibraryDefaults.builtInID, "petdex.boba"])
    #expect(renamed[0].displayName == "Home")

    let stock = AiboLibraryCodec.persistableRecords(from: [.builtInDefault, boba])
    #expect(stock.map(\.id) == ["petdex.boba"])
}

@Test func aiboLibraryCodecPreservesInstallMetadata() throws {
    let installedAt = Date(timeIntervalSince1970: 1_704_067_200)
    let file = AiboLibraryFile(
        selectedID: "petdex.boba",
        records: [
            AiboLibraryRecord(
                id: "petdex.boba",
                kind: .petdex,
                displayName: "Boba",
                relativePath: "petdex/boba",
                slug: "boba",
                spriteFileName: "spritesheet.webp",
                installedAt: installedAt,
                installSource: "https://petdex.dev/pets/boba"
            ),
        ]
    )
    let roundTrip = try AiboLibraryCodec.decode(AiboLibraryCodec.encode(file))
    #expect(roundTrip.records[0].installedAt == installedAt)
    #expect(roundTrip.records[0].installSource == "https://petdex.dev/pets/boba")
}

@Test func aiboLibraryCodecDecodesRecordsWithoutInstallMetadata() throws {
    let json = """
    {
      "selectedID" : "builtin.default",
      "records" : [
        {
          "displayName" : "Boba",
          "id" : "petdex.boba",
          "kind" : "petdex",
          "relativePath" : "petdex/boba",
          "slug" : "boba",
          "spriteFileName" : "spritesheet.webp"
        }
      ]
    }
    """
    let file = try AiboLibraryCodec.decode(Data(json.utf8))
    #expect(file.records[0].installedAt == nil)
    #expect(file.records[0].installSource == nil)
}

@Test func aiboLibraryOrderingPutsNewestInstallFirst() {
    let older = AiboLibraryRecord(
        id: "static.old",
        kind: .staticImage,
        displayName: "Old",
        relativePath: "static/old.png",
        installedAt: Date(timeIntervalSince1970: 100)
    )
    let newer = AiboLibraryRecord(
        id: "static.new",
        kind: .staticImage,
        displayName: "New",
        relativePath: "static/new.png",
        installedAt: Date(timeIntervalSince1970: 200)
    )
    let sorted = AiboLibraryOrdering.installedAtNewestFirst([older, .builtInDefault, newer])
    #expect(sorted.map(\.id) == ["static.new", "static.old", AiboLibraryDefaults.builtInID])
}

@Test func aiboLibraryOrderingSortsByNameAndSize() {
    let boba = AiboLibraryRecord(
        id: "petdex.boba",
        kind: .petdex,
        displayName: "Boba",
        relativePath: "petdex/boba"
    )
    let apple = AiboLibraryRecord(
        id: "static.apple",
        kind: .staticImage,
        displayName: "Apple",
        relativePath: "static/apple.png"
    )
    let byName = AiboLibraryOrdering.byDisplayName([boba, apple, .builtInDefault])
    #expect(byName.map(\.displayName) == ["Apple", "Boba", "Default"])

    let bySize = AiboLibraryOrdering.bySizeLargestFirst(
        [apple, boba, .builtInDefault],
        bytesForID: [
            apple.id: 10,
            boba.id: 50,
            AiboLibraryDefaults.builtInID: 0,
        ]
    )
    #expect(bySize.map(\.id) == [boba.id, apple.id, AiboLibraryDefaults.builtInID])
}

@Test func petdexSpriteLayoutDetectsV1AndV2() {
    let v1 = PetdexSpriteLayout(pixelWidth: 1536, pixelHeight: 1872)
    #expect(v1?.rows == 9)
    #expect(v1?.scale == 1)
    #expect(v1?.supportsLookDirections == false)
    #expect(v1?.lookFrameRect(index: 0) == nil)

    let v2 = PetdexSpriteLayout(pixelWidth: 1536, pixelHeight: 2288)
    #expect(v2?.rows == 11)
    #expect(v2?.supportsLookDirections == true)

    let scaled = PetdexSpriteLayout(pixelWidth: 3072, pixelHeight: 4576)
    #expect(scaled?.scale == 2)
    #expect(scaled?.rows == 11)

    #expect(PetdexSpriteLayout(pixelWidth: 100, pixelHeight: 100) == nil)
}

@Test func petdexLookDirectionMatchesPetxClockwiseFromUp() {
    #expect(PetdexLookDirection.resolve(deltaX: 0, deltaYDown: -1)?.index == 0)
    #expect(PetdexLookDirection.resolve(deltaX: 1, deltaYDown: 0)?.index == 4)
    #expect(PetdexLookDirection.resolve(deltaX: 0, deltaYDown: 1)?.index == 8)
    #expect(PetdexLookDirection.resolve(deltaX: -1, deltaYDown: 0)?.index == 12)
    #expect(PetdexLookDirection.resolve(degrees: 31)?.index == 1)
    #expect(PetdexLookDirection.resolve(degrees: -22.5)?.index == 15)
    #expect(PetdexLookDirection.resolve(deltaX: 0.1, deltaYDown: 0.1, deadzone: 0.2) == nil)
    #expect(PetdexLookDirection.resolve(deltaX: 0, deltaYDown: 0) == nil)
}

@Test func petdexLookFrameRectsUseRows9And10() {
    let v2 = PetdexSpriteLayout(pixelWidth: 1536, pixelHeight: 2288)
    let up = v2?.lookFrameRect(index: 0)
    let right = v2?.lookFrameRect(index: 4)
    let down = v2?.lookFrameRect(index: 8)
    let left = v2?.lookFrameRect(index: 12)
    let wrap = v2?.lookFrameRect(index: 15)
    #expect(up?.x == 0 && up?.y == 1872)
    #expect(right?.x == 768 && right?.y == 1872)
    #expect(down?.x == 0 && down?.y == 2080)
    #expect(left?.x == 768 && left?.y == 2080)
    #expect(wrap?.x == 1344 && wrap?.y == 2080)
    #expect(v2?.lookFrameRect(index: 16) == nil)
}

@Test func petdexSpriteStateMapperMapsActivity() {
    #expect(PetdexSpriteStateMapper.state(for: .idle) == .idle)
    #expect(PetdexSpriteStateMapper.state(for: .thinking) == .jumping)
    #expect(PetdexSpriteStateMapper.state(for: .usingTool("Read")) == .review)
    #expect(PetdexSpriteStateMapper.state(for: .usingTool("Shell")) == .running)
    #expect(PetdexSpriteStateMapper.state(for: .waiting) == .waiting)
    #expect(PetdexSpriteStateMapper.state(for: .failed) == .failed)
    #expect(PetdexSpriteStateMapper.state(for: .done) == .waving)
}

@Test func hookSpriteMappingDefaultsAndOverrides() {
    #expect(HookSpriteMapping.defaultSprite(agent: .cursor, hookEventName: "preToolUse") == .running)
    #expect(HookSpriteMapping.defaultSprite(agent: .codex, hookEventName: "PermissionRequest") == .waiting)

    var file = HookSpriteMappingFile()
    file.cursor["preToolUse"] = PetdexSpriteState.review.rawValue
    #expect(
        HookSpriteMapping.resolve(
            agent: .cursor,
            hookEventName: "preToolUse",
            activity: .usingTool("Shell"),
            overrides: file
        ) == .review
    )
    #expect(
        HookSpriteMapping.resolve(
            agent: .cursor,
            hookEventName: nil,
            activity: .idle,
            overrides: file
        ) == .idle
    )
    #expect(HookSpriteMapping.configurableHooks(for: .cursor).contains("stop"))
    #expect(HookSpriteMapping.configurableHooks(for: .codex).contains("Stop"))
    #expect(HookSpriteMapping.configurableHooks(for: .deepseek).contains("PermissionRequest"))
    #expect(
        HookSpriteMapping.defaultSprite(agent: .deepseek, hookEventName: "PreToolUse") == .running
    )
}

@Test func aiboActionMappingDefaultsToRunDirections() {
    #expect(AiboActionMapping.defaultSprite(for: .dragLeft) == .runningLeft)
    #expect(AiboActionMapping.defaultSprite(for: .dragRight) == .runningRight)
    #expect(AiboActionMapping.resolve(.dragLeft, overrides: [:]) == .runningLeft)
    #expect(AiboActionMapping.resolve(.dragRight, overrides: [:]) == .runningRight)

    let overrides = [AiboUserAction.dragLeft.rawValue: PetdexSpriteState.jumping.rawValue]
    #expect(AiboActionMapping.resolve(.dragLeft, overrides: overrides) == .jumping)
    #expect(AiboActionMapping.resolve(.dragRight, overrides: overrides) == .runningRight)

    let invalid = [AiboUserAction.dragLeft.rawValue: "not-a-sprite"]
    #expect(AiboActionMapping.resolve(.dragLeft, overrides: invalid) == .runningLeft)
}

@Test func aiboActionOverlayYieldsToHookSprite() {
    #expect(
        AiboActionMapping.overlay(hookSprite: .idle, userActionSprite: .runningLeft) == .runningLeft
    )
    #expect(
        AiboActionMapping.overlay(hookSprite: .jumping, userActionSprite: .runningLeft) == .jumping
    )
    #expect(
        AiboActionMapping.overlay(hookSprite: .idle, userActionSprite: nil) == .idle
    )
}

@Test func petdexInstallerWritesPackViaInjectedFetch() async throws {
    let slug = "test-pet-\(UUID().uuidString.prefix(8).lowercased())"
    let petJSON = #"{"id":"\#(slug)","displayName":"Test","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp"}"#
    let spriteBytes = Data([0x52, 0x49, 0x46, 0x46]) // tiny stub; layout not validated at install

    let installer = PetdexInstaller { url, _ in
        let path = url.path
        if path.contains("/api/install-pet/") {
            let body = """
            {"ok":true,"pet":{"slug":"\(slug)","displayName":"Test","petJsonUrl":"https://example.com/pet.json","spritesheetUrl":"https://example.com/sprite.webp","spriteExt":"webp"}}
            """
            return Data(body.utf8)
        }
        if path.hasSuffix("pet.json") {
            return Data(petJSON.utf8)
        }
        if path.hasSuffix("sprite.webp") {
            return spriteBytes
        }
        throw PetdexInstallError.downloadFailed
    }

    let record = try await installer.install(slug: slug)
    #expect(record.slug == slug)
    #expect(record.id == "petdex.\(slug)")

    let dir = AiboPaths.petdexAiboDirectory(slug: slug)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pet.json").path))
    #expect(
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("spritesheet.webp").path)
    )

    try? FileManager.default.removeItem(at: dir)
}

@Test func localAiboImporterClassifiesImageAndZip() {
    #expect(LocalAiboImporter.classify(url: URL(fileURLWithPath: "/tmp/aibo.png")) == .staticImage)
    #expect(LocalAiboImporter.classify(url: URL(fileURLWithPath: "/tmp/aibo.WEBP")) == .staticImage)
    #expect(LocalAiboImporter.classify(url: URL(fileURLWithPath: "/tmp/pack.zip")) == .zipArchive)
    #expect(LocalAiboImporter.classify(url: URL(fileURLWithPath: "/tmp/notes.pdf")) == nil)
}

@Test func localAiboImporterSanitizesSlug() {
    #expect(LocalAiboImporter.sanitizeSlug("boba") == "boba")
    #expect(LocalAiboImporter.sanitizeSlug("Phoebibi") == "phoebibi")
    #expect(LocalAiboImporter.sanitizeSlug("My Pet!") == "my-pet")
    #expect(LocalAiboImporter.sanitizeSlug("你好") == nil)
}

@Test func localAiboImporterInstallsPackFromDirectory() throws {
    let slug = "local-pack-\(UUID().uuidString.prefix(8).lowercased())"
    let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-pack-src-\(slug)", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let petJSON = #"{"id":"\#(slug)","displayName":"Local Pack","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp"}"#
    try Data(petJSON.utf8).write(to: source.appendingPathComponent("pet.json"))
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: source.appendingPathComponent("spritesheet.webp"))

    let record = try LocalAiboImporter.installPack(fromDirectory: source, fallbackSlug: "ignored")
    #expect(record.id == "petdex.\(slug)")
    #expect(record.kind == .petdex)
    #expect(record.displayName == "Local Pack")
    #expect(record.installSource == "Local")
    #expect(record.spriteFileName == "spritesheet.webp")
    #expect(record.spriteVersionNumber == 2)

    let dest = AiboPaths.petdexAiboDirectory(slug: slug)
    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("pet.json").path))
    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("spritesheet.webp").path))

    try? FileManager.default.removeItem(at: source)
    try? FileManager.default.removeItem(at: dest)
}

@Test func localAiboImporterRejectsPackWithoutSpritesheet() throws {
    let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-pack-bad-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(#"{"id":"bad-pack","displayName":"Bad"}"#.utf8)
        .write(to: source.appendingPathComponent("pet.json"))
    defer { try? FileManager.default.removeItem(at: source) }

    #expect(throws: LocalAiboImportError.invalidPack) {
        try LocalAiboImporter.installPack(fromDirectory: source, fallbackSlug: "bad-pack")
    }
}

@Test func localAiboImporterRejectsPathTraversalSpritesheet() throws {
    let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-pack-traverse-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(#"{"id":"traverse-pack","spritesheetPath":"../outside.webp"}"#.utf8)
        .write(to: source.appendingPathComponent("pet.json"))
    defer { try? FileManager.default.removeItem(at: source) }

    #expect(throws: LocalAiboImportError.invalidPack) {
        try LocalAiboImporter.installPack(fromDirectory: source, fallbackSlug: "traverse-pack")
    }
}

@Test func localAiboImporterInstallsPackFromZip() throws {
    let slug = "local-zip-\(UUID().uuidString.prefix(8).lowercased())"
    let fileManager = FileManager.default
    let source = fileManager.temporaryDirectory
        .appendingPathComponent("aibo-zip-src-\(slug)", isDirectory: true)
    let nested = source.appendingPathComponent(slug, isDirectory: true)
    try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
    let petJSON = #"{"id":"\#(slug)","displayName":"Zipped","spritesheetPath":"spritesheet.webp"}"#
    try Data(petJSON.utf8).write(to: nested.appendingPathComponent("pet.json"))
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: nested.appendingPathComponent("spritesheet.webp"))

    let zipURL = fileManager.temporaryDirectory.appendingPathComponent("\(slug).zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--keepParent", source.path, zipURL.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let record = try LocalAiboImporter.installPack(fromArchive: zipURL)
    #expect(record.slug == slug)
    #expect(record.installSource == "Local")

    let dest = AiboPaths.petdexAiboDirectory(slug: slug)
    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("pet.json").path))

    try? fileManager.removeItem(at: source)
    try? fileManager.removeItem(at: zipURL)
    try? fileManager.removeItem(at: dest)
}

@Test func migrateLegacyLibraryDirectoryMovesPetsToAibos() throws {
    let fileManager = FileManager.default
    let support = fileManager.temporaryDirectory
        .appendingPathComponent("aibo-migrate-\(UUID().uuidString)", isDirectory: true)
    let legacy = support.appendingPathComponent(AiboPaths.legacyPetsDirectoryName, isDirectory: true)
    let destination = support.appendingPathComponent(AiboPaths.aibosDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("ok".utf8).write(to: legacy.appendingPathComponent("library.json"))

    AiboPaths.migrateLegacyLibraryDirectory(in: support, fileManager: fileManager)

    #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("library.json").path))
    #expect(fileManager.fileExists(atPath: legacy.path) == false)

    try? fileManager.removeItem(at: support)
}

@Test func migrateLegacyLibraryDirectoryLeavesExistingAibosAlone() throws {
    let fileManager = FileManager.default
    let support = fileManager.temporaryDirectory
        .appendingPathComponent("aibo-migrate-\(UUID().uuidString)", isDirectory: true)
    let legacy = support.appendingPathComponent(AiboPaths.legacyPetsDirectoryName, isDirectory: true)
    let destination = support.appendingPathComponent(AiboPaths.aibosDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: legacy.appendingPathComponent("library.json"))
    try Data("new".utf8).write(to: destination.appendingPathComponent("library.json"))

    AiboPaths.migrateLegacyLibraryDirectory(in: support, fileManager: fileManager)

    let kept = try String(contentsOf: destination.appendingPathComponent("library.json"), encoding: .utf8)
    #expect(kept == "new")
    #expect(fileManager.fileExists(atPath: legacy.path))

    try? fileManager.removeItem(at: support)
}
