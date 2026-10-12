import Foundation
import Testing
@testable import AiboCore

@Test func extensionCatalogDecodesRepositoryIndex() throws {
    let url = repositoryRoot().appendingPathComponent("Extensions/catalog.json")
    let catalog = try ExtensionCatalog.decode(Data(contentsOf: url))
    #expect(catalog.apiVersion == 1)
    #expect(catalog.repository == "fenxer/agent-aibo")
    #expect(catalog.ref == "main")
    #expect(catalog.listed.map(\.id) == ["dev.aibo.ai-provider", "dev.aibo.translate", "dev.aibo.alt-text"])
    let translate = try #require(catalog.listed.first { $0.id == "dev.aibo.translate" })
    #expect(translate.path == "Extensions/dev.aibo.translate")
    #expect(translate.compatibilityAibo == ">=1.1.0")
    #expect(translate.capabilities == ["llm"])
    #expect(translate.displayCopy(preferredLanguage: "zh-Hans").name == "翻译")
    #expect(translate.displayCopy(preferredLanguage: "en").name == "Translate")
    #expect(translate.icon.symbol == "character.bubble.fill")
    let altText = try #require(catalog.listed.first { $0.id == "dev.aibo.alt-text" })
    #expect(altText.path == "Extensions/dev.aibo.alt-text")
    #expect(altText.slug == "alt-text")
    #expect(altText.capabilities == ["llm"])
    #expect(altText.displayCopy(preferredLanguage: "zh-Hans").name == "替代文本")
    #expect(altText.displayCopy(preferredLanguage: "en").name == "Alt Text")
    #expect(altText.icon.symbol == "photo.on.rectangle.angled.fill")
}

@Test func extensionCatalogResolvesLocalRepositoryRoot() {
    let file = URL(fileURLWithPath: "/Users/fenx/aibo/Extensions/catalog.json")
    #expect(
        ExtensionCatalog.repositoryRoot(catalogFile: file)?.path == "/Users/fenx/aibo"
    )
    let elsewhere = URL(fileURLWithPath: "/Users/fenx/aibo/Other/catalog.json")
    #expect(ExtensionCatalog.repositoryRoot(catalogFile: elsewhere) == nil)
}

@Test func extensionCatalogBuildsGitHubURLs() throws {
    let raw = try #require(
        ExtensionCatalog.rawFileURL(
            repository: "fenxer/agent-aibo",
            ref: "main",
            path: "Extensions/catalog.json"
        )
    )
    #expect(raw.absoluteString == "https://raw.githubusercontent.com/fenxer/agent-aibo/main/Extensions/catalog.json")
    #expect(ExtensionCatalogLocation.rawCatalogURL == raw)

    let catalog = ExtensionCatalog(
        apiVersion: 1,
        repository: "fenxer/agent-aibo",
        ref: "main",
        updated: "",
        revoked: [],
        extensions: []
    )
    let contents = try #require(catalog.contentsAPIURL(path: "Extensions/dev.aibo.translate"))
    #expect(
        contents.absoluteString
            == "https://api.github.com/repos/fenxer/agent-aibo/contents/Extensions/dev.aibo.translate?ref=main"
    )
    #expect(catalog.contentsAPIURL(path: "../secrets") == nil)
}

@Test func extensionCatalogSkipsRevokedAndUnknownAPI() throws {
    let json = """
    {"apiVersion":1,"repository":"fenxer/agent-aibo","ref":"main","revoked":["dev.aibo.old"],
     "extensions":[
       {"id":"dev.aibo.old","name":"Old","description":"Gone","version":"1.0.0","path":"Extensions/old"},
       {"id":"dev.aibo.next","name":"Next","description":"Later","version":"1.0.0","extensionApiVersion":2,"path":"Extensions/next"},
       {"id":"dev.aibo.ok","name":"Ok","description":"Here","version":"1.0.0","path":"Extensions/ok"}
     ]}
    """
    let catalog = try ExtensionCatalog.decode(Data(json.utf8))
    #expect(catalog.listed.map(\.id) == ["dev.aibo.ok"])
}

@Test func extensionVersionComparesNumericComponents() {
    #expect(ExtensionVersion.isNewer("1.0.1", than: "1.0.0"))
    #expect(ExtensionVersion.isNewer("1.2.0", than: "1.1.9"))
    #expect(ExtensionVersion.isNewer("1.0.0", than: "1.0") == false)
    #expect(ExtensionVersion.isNewer("1.0.0", than: "1.0.0") == false)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
