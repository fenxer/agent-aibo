import Foundation
import Testing
@testable import AiboCore

@Test func extensionManifestDecodesPrototypeProvider() throws {
    let url = repositoryRoot()
        .appendingPathComponent("Extensions/dev.aibo.ai-provider/manifest.json")
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
    #expect(ExtensionManifestValidator.validate(manifest) == nil)
    #expect(manifest.providesModel)
    #expect(manifest.entry == "main.js")
    #expect(manifest.settings?.orderedKeys == ["format", "baseURL", "model", "apiKey"])
    #expect(manifest.settings?.properties["apiKey"]?.sensitive == true)
}

@Test func extensionManifestDecodesPrototypeTranslator() throws {
    let url = repositoryRoot()
        .appendingPathComponent("Extensions/dev.aibo.translate/manifest.json")
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: url))
    #expect(ExtensionManifestValidator.validate(manifest) == nil)
    #expect(manifest.hasManualTrigger)
    #expect(manifest.usesModel)
    #expect(manifest.prompt?.properties["target"]?.oneOf.map(\.value) == ["zh-Hans", "en", "ja"])
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
    #expect(completion.content.first?.actions.first?.copyText == "hello")

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
