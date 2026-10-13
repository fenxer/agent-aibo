import Foundation
import Testing
@testable import AiboCore

@Test func extensionManifestDecodesPrototypeProvider() throws {
    let url = repositoryRoot()
        .appendingPathComponent("Extensions/dev.aibo.ai-provider/manifest.json")
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
    #expect(ExtensionManifestValidator.validate(manifest) == nil)
    #expect(manifest.providesModel)
    #expect(manifest.exports.map(\.capability) == ["llm"])
    #expect(manifest.exports.first?.fields == ["displayName", "format", "baseURL", "model"])
    #expect(manifest.entry == "main.js")
    #expect(manifest.settings?.orderedKeys == ["format", "baseURL", "model", "apiKey"])
    #expect(manifest.settings?.properties["apiKey"]?.sensitive == true)
    #expect(manifest.icon.symbol == "sparkle")
    #expect(manifest.icon.backgroundHex(dark: false) == "#0088FF")
    #expect(manifest.icon.backgroundHex(dark: true) == "#0088FF")
    #expect(manifest.icon.symbolHex(dark: false) == "#FFFFFF")
    #expect(manifest.icon.symbolHex(dark: true) == "#FFFFFF")
    #expect(manifest.icon.image == nil)
    #expect(manifest.slug == "ai-provider")
    #expect(manifest.requiredCapabilities.isEmpty)
}

@Test func extensionManifestDecodesPrototypeTranslator() throws {
    let url = repositoryRoot()
        .appendingPathComponent("Extensions/dev.aibo.translate/manifest.json")
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
    #expect(ExtensionManifestValidator.validate(manifest) == nil)
    #expect(manifest.hasManualTrigger)
    #expect(manifest.usesModel)
    #expect(manifest.settings?.orderedKeys == ["provider"])
    #expect(manifest.settings?.properties["provider"]?.source == "llm")
    #expect(manifest.prompt?.properties["target"]?.oneOf.map(\.value) == ["zh-Hans", "en", "ja"])
    #expect(manifest.prompt?.fieldGroups() == [["text", "target"]])
    #expect(manifest.icon.symbol == "character.bubble.fill")
    #expect(manifest.icon.backgroundHex(dark: false) == nil)
    #expect(manifest.icon.backgroundHex(dark: true) == nil)
    #expect(manifest.icon.symbolHex(dark: false) == nil)
    #expect(manifest.slug == "translate")
    #expect(manifest.requiredCapabilities == ["llm"])
    #expect(manifest.accepts.isEmpty)
}

@Test func extensionManifestDecodesAltText() throws {
    let url = repositoryRoot()
        .appendingPathComponent("Extensions/dev.aibo.alt-text/manifest.json")
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
    #expect(ExtensionManifestValidator.validate(manifest) == nil)
    #expect(manifest.slug == "alt-text")
    #expect(manifest.hasManualTrigger)
    #expect(manifest.accepts == ["png", "jpg", "jpeg"])
    #expect(manifest.requiredCapabilities == ["llm"])
    #expect(manifest.settings?.orderedKeys == ["prompt", "model", "language"])
    #expect(manifest.settings?.properties["model"]?.source == "llm")
    #expect(manifest.settings?.properties["prompt"]?.defaultValue?.stringValue == "生成图片的 alt text，简洁一些")
    #expect(manifest.settings?.properties["language"]?.defaultValue?.stringValue == "zh-Hans")
    #expect(manifest.prompt?.properties["image"]?.control == "image")
    #expect(manifest.prompt?.required == ["image"])
    #expect(manifest.icon.symbol == "photo.on.rectangle.angled.fill")
    #expect(manifest.icon.backgroundHex(dark: false) == "#FF9500")
    #expect(manifest.icon.symbolHex(dark: false) == "#FFFFFF")
}

@Test func extensionPromptSectionsGroupFields() throws {
    let json = """
    {
      "type": "object",
      "order": ["text", "tone", "formal", "notify"],
      "sections": [{ "fields": ["tone", "formal"] }],
      "properties": {
        "text": { "type": "string", "control": "text" },
        "tone": {
          "type": "string",
          "control": "menu",
          "oneOf": [{ "const": "plain", "title": "Plain" }]
        },
        "formal": { "type": "boolean", "control": "switch" },
        "notify": {
          "type": "string",
          "control": "radio",
          "oneOf": [
            { "const": "a", "title": "A" },
            { "const": "b", "title": "B" }
          ]
        }
      }
    }
    """
    let schema = try JSONDecoder().decode(ExtensionObjectSchema.self, from: Data(json.utf8))
    #expect(schema.fieldGroups() == [["text"], ["tone", "formal"], ["notify"]])
    #expect(schema.properties["formal"]?.control == "switch")
    var manifest = sampleManifest()
    manifest.prompt = schema
    #expect(ExtensionManifestValidator.validate(manifest) == nil)

    var broken = schema
    broken.sections = [ExtensionFieldSection(fields: ["missing"])]
    manifest.prompt = broken
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidSchema)

    var unknown = schema
    var textField = unknown.properties["text"] ?? ExtensionFieldSchema(type: "string")
    textField.control = "slider"
    unknown.properties["text"] = textField
    manifest.prompt = unknown
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidSchema)
}

@Test func extensionIconDecodesImageAndAppearanceColors() throws {
    let image = try JSONDecoder().decode(
        ExtensionIcon.self,
        from: Data(#"{"image":"icon.png"}"#.utf8)
    )
    #expect(image.image == "icon.png")
    #expect(image.symbol == ExtensionIcon.defaultSymbol)

    let lightOnly = try JSONDecoder().decode(
        ExtensionIcon.self,
        from: Data(
            ##"{"symbol":"sparkle","background":{"light":"#111111"}}"##.utf8
        )
    )
    #expect(lightOnly.backgroundHex(dark: false) == "#111111")
    #expect(lightOnly.backgroundHex(dark: true) == "#111111")

    let darkOnly = try JSONDecoder().decode(
        ExtensionIcon.self,
        from: Data(
            ##"{"background":{"dark":"#EEEEEE"}}"##.utf8
        )
    )
    #expect(darkOnly.symbol == ExtensionIcon.defaultSymbol)
    #expect(darkOnly.backgroundHex(dark: false) == "#EEEEEE")
    #expect(darkOnly.backgroundHex(dark: true) == "#EEEEEE")

    var manifest = sampleManifest()
    manifest.icon = ExtensionIcon(image: "../icon.png")
    #expect(ExtensionManifestValidator.validate(manifest) == .unsafeRelativePath("../icon.png"))
    manifest.icon = ExtensionIcon(symbol: "sparkle", lightBackground: "red")
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidIcon("red"))
}

@Test func extensionSlugAndInstallPolicy() {
    var manifest = sampleManifest()
    #expect(manifest.slug == nil)
    var plain = manifest
    plain.capabilities = []
    #expect(ExtensionInstallPolicy.block(installing: plain, alongside: []) == nil)

    manifest.slug = "Translate"
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidSlug("Translate"))
    manifest.slug = "translate"
    #expect(ExtensionManifestValidator.validate(manifest) == nil)

    let provider = providerManifest()
    #expect(
        ExtensionInstallPolicy.block(installing: manifest, alongside: [])
            == ExtensionInstallBlock(missingCapabilities: ["llm"])
    )
    #expect(ExtensionInstallPolicy.block(installing: manifest, alongside: [provider]) == nil)
    #expect(ExtensionInstallPolicy.block(installing: provider, alongside: []) == nil)

    var other = provider
    other.id = "dev.aibo.other"
    other.slug = "translate"
    other.provides = ["llm"]
    #expect(
        ExtensionInstallPolicy.block(installing: manifest, alongside: [other])
            == ExtensionInstallBlock(duplicateSlug: "translate")
    )
    other.provides = []
    #expect(
        ExtensionInstallPolicy.block(installing: manifest, alongside: [other])
            == ExtensionInstallBlock(missingCapabilities: ["llm"], duplicateSlug: "translate")
    )
    #expect(ExtensionInstallPolicy.block(installing: manifest, alongside: [provider, manifest]) == nil)

    manifest.rewrite = true
    manifest.capabilities = []
    #expect(manifest.requiredCapabilities == ["llm"])

    #expect(ExtensionLink.slug(from: URL(string: "aibo://extension/Translate")!) == "translate")
    #expect(ExtensionLink.slug(from: URL(string: "aibo://extension/translate?x=1")!) == "translate")
    #expect(ExtensionLink.slug(from: URL(string: "aibo:///extension/translate")!) == "translate")
    #expect(ExtensionLink.slug(from: URL(string: "aibo://extension/translate/extra")!) == nil)
    #expect(ExtensionLink.slug(from: URL(string: "https://example.com/extension/translate")!) == nil)
}

@Test func extensionManifestRejectsPathEscape() {
    var manifest = sampleManifest()
    manifest.entry = "../main.js"
    #expect(ExtensionManifestValidator.validate(manifest) == .unsafeRelativePath("../main.js"))
    manifest.entry = "/tmp/main.js"
    #expect(ExtensionManifestValidator.validate(manifest) == .unsafeRelativePath("/tmp/main.js"))
}

@Test func extensionRoundCodecReadsCompletionAndFetchRequest() throws {
    let complete = """
    {"resultType":"complete","output":{"text":"hello"},"content":[{"type":"bubble","summary":"hello","actions":[{"title":"Copy","copy":"hello"}]}]}
    """
    let decoded = try ExtensionRoundCodec.decode(Data(complete.utf8))
    guard case .complete(let completion) = decoded else {
        Issue.record("expected complete")
        return
    }
    #expect(completion.output["text"]?.stringValue == "hello")
    #expect(completion.content.first?.outcome == .success)
    #expect(completion.content.first?.actions.first?.copyText == "hello")

    let failed = """
    {"resultType":"complete","content":[{"type":"bubble","outcome":"failure","summary":"{\\"error\\":\\"bad model\\"}"}]}
    """
    let failedRound = try ExtensionRoundCodec.decode(Data(failed.utf8))
    guard case .complete(let failedCompletion) = failedRound else {
        Issue.record("expected failure bubble")
        return
    }
    #expect(failedCompletion.content.first?.outcome == .failure)

    let warned = """
    {"resultType":"complete","content":[{"type":"bubble","outcome":"warning","summary":"Check the input."}]}
    """
    let warnedRound = try ExtensionRoundCodec.decode(Data(warned.utf8))
    guard case .complete(let warnedCompletion) = warnedRound else {
        Issue.record("expected warning bubble")
        return
    }
    #expect(warnedCompletion.content.first?.outcome == .warning)

    let unknown = """
    {"resultType":"complete","content":[{"type":"bubble","outcome":"partial","summary":"not a result"}]}
    """
    let unknownRound = try ExtensionRoundCodec.decode(Data(unknown.utf8))
    guard case .complete(let unknownCompletion) = unknownRound else {
        Issue.record("expected unknown outcome")
        return
    }
    #expect(unknownCompletion.content.first?.outcome == .failure)

    let required = """
    {"resultType":"input_required","requestState":"","inputRequests":{"http":{"method":"aibo/fetch","params":{"url":"https://api.openai.com/v1/chat/completions"}}}}
    """
    let round = try ExtensionRoundCodec.decode(Data(required.utf8))
    guard case .inputRequired(let requests, _) = round else {
        Issue.record("expected input_required")
        return
    }
    #expect(requests["http"]?.method == "aibo/fetch")
}

@Test func extensionURLPolicyAllowsOnlyListedHTTPSHosts() {
    let hosts: Set<String> = ["api.openai.com"]
    #expect(ExtensionURLPolicy.rejection(urlString: "https://api.openai.com/v1/chat/completions", allowedHosts: hosts) == nil)
    #expect(ExtensionURLPolicy.rejection(urlString: "http://api.openai.com/v1", allowedHosts: hosts) == "https-only")
    #expect(ExtensionURLPolicy.rejection(urlString: "https://evil.example/v1", allowedHosts: hosts) == "host-not-allowed")
    #expect(ExtensionURLPolicy.rejection(urlString: "https://127.0.0.1/v1", allowedHosts: ["127.0.0.1"]) == "private-address")
    #expect(ExtensionURLPolicy.rejection(urlString: "https://localhost/v1", allowedHosts: ["localhost"]) == "local-host")
}

@Test func extensionCopyUsesLocaleStrings() {
    let manifest = sampleManifest()
    let copy = ExtensionCopyResolver.resolve(
        manifest: manifest,
        strings: ["name": "翻译", "description": "说明", "io.inputs.text": "文本", "io.outputs.text": "文本"]
    )
    #expect(copy.name == "翻译")
    #expect(copy.inputs == ["文本"])
    #expect(copy.outputs == ["文本"])
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func providerManifest() -> ExtensionManifest {
    var manifest = sampleManifest()
    manifest.id = "dev.aibo.ai-provider"
    manifest.slug = "ai-provider"
    manifest.capabilities = []
    manifest.provides = ["llm"]
    manifest.triggers = []
    return manifest
}

private func sampleManifest() -> ExtensionManifest {
    ExtensionManifest(
        apiVersion: 1,
        id: "dev.aibo.translate",
        name: "Translate",
        summary: "Translate text.",
        version: "1.0.0",
        author: "aibo",
        runtime: "js",
        entry: "main.js",
        triggers: [ExtensionTrigger(kind: "manual")],
        accepts: [],
        capabilities: ["llm"],
        provides: [],
        network: ExtensionNetwork(hosts: []),
        settings: nil,
        prompt: nil,
        rewrite: false,
        localization: nil,
        io: ExtensionIO(
            inputs: [ExtensionIOItem(id: "text", kind: "text")],
            outputs: [ExtensionIOItem(id: "text", kind: "text")]
        )
    )
}
