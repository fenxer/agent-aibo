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
}

@Test func petLibrarySnapshotIncludesBuiltInAndFixesSelection() throws {
    let file = PetLibraryFile(
        selectedID: "missing",
        records: [
            PetLibraryRecord(
                id: "petdex.boba",
                kind: .petdex,
                displayName: "Boba",
                relativePath: "petdex/boba",
                slug: "boba",
                spriteFileName: "spritesheet.webp"
            ),
        ]
    )
    let snap = PetLibraryCodec.snapshot(from: file)
    #expect(snap.selectedID == PetLibraryDefaults.builtInID)
    #expect(snap.records.first?.id == PetLibraryDefaults.builtInID)
    #expect(snap.records.contains(where: { $0.id == "petdex.boba" }))

    let roundTrip = try PetLibraryCodec.decode(PetLibraryCodec.encode(file))
    #expect(roundTrip.records.count == 1)
}

@Test func petdexSpriteLayoutDetectsV1AndV2() {
    let v1 = PetdexSpriteLayout(pixelWidth: 1536, pixelHeight: 1872)
    #expect(v1?.rows == 9)
    #expect(v1?.scale == 1)

    let v2 = PetdexSpriteLayout(pixelWidth: 1536, pixelHeight: 2288)
    #expect(v2?.rows == 11)

    let scaled = PetdexSpriteLayout(pixelWidth: 3072, pixelHeight: 4576)
    #expect(scaled?.scale == 2)
    #expect(scaled?.rows == 11)

    #expect(PetdexSpriteLayout(pixelWidth: 100, pixelHeight: 100) == nil)
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

    let dir = AiboPaths.petdexPetDirectory(slug: slug)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pet.json").path))
    #expect(
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("spritesheet.webp").path)
    )

    try? FileManager.default.removeItem(at: dir)
}
