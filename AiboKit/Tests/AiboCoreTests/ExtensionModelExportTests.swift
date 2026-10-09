import Foundation
import Testing
@testable import AiboCore

@Test func modelExportOmitsSecretsAndDefaultsToTheFirstProvider() {
    let models = ExtensionModelExport.models(
        pluginID: "dev.aibo.ai-provider",
        declaredFields: ["displayName", "format", "baseURL", "model", "apiKey"],
        providers: [
            ExtensionProviderRecord(
                id: "first",
                displayName: "Work",
                values: [
                    "format": "chat-completions",
                    "baseURL": "https://api.openai.com/v1",
                    "model": "gpt-4o-mini",
                    "apiKey": "secret",
                ]
            ),
            ExtensionProviderRecord(
                id: "second",
                displayName: "  ",
                values: [
                    "format": "google-interactions",
                    "baseURL": "",
                    "model": "gemini-3.6-flash",
                ]
            ),
        ],
        sensitiveKeys: ["apiKey"]
    )

    #expect(models.map(\.id) == ["dev.aibo.ai-provider/first", "dev.aibo.ai-provider/second"])
    #expect(models[0].title == "Work")
    #expect(models[0].fields["displayName"] == "Work")
    #expect(models[0].fields["model"] == "gpt-4o-mini")
    #expect(models[0].fields["apiKey"] == nil)
    #expect(models[1].title == "gemini-3.6-flash")
    #expect(models[1].fields["displayName"] == "  ")

    #expect(ExtensionModelExport.resolve(saved: nil, models: models)?.providerID == "first")
    #expect(ExtensionModelExport.resolve(saved: "  ", models: models)?.providerID == "first")
    #expect(ExtensionModelExport.resolve(saved: "gone", models: models)?.providerID == "first")
    #expect(ExtensionModelExport.resolve(saved: models[1].id, models: models)?.providerID == "second")
    #expect(ExtensionModelExport.resolve(saved: "first", models: []) == nil)
}

@Test func manifestRejectsSecretAndUnprovidedExports() {
    var manifest = ExtensionManifest(
        apiVersion: 1,
        id: "dev.aibo.ai-provider",
        name: "AI Provider",
        summary: "Models.",
        version: "1.0.0",
        author: "aibo",
        runtime: "js",
        entry: "main.js",
        triggers: [],
        accepts: [],
        capabilities: [],
        provides: ["llm"],
        network: ExtensionNetwork(hosts: []),
        settings: ExtensionObjectSchema(
            properties: [
                "apiKey": ExtensionFieldSchema(type: "string", sensitive: true),
                "model": ExtensionFieldSchema(type: "string"),
            ]
        ),
        prompt: nil,
        rewrite: false,
        localization: nil,
        io: ExtensionIO(inputs: [], outputs: [])
    )
    manifest.exports = [ExtensionExport(capability: "llm", fields: ["model", "apiKey"])]
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidSchema)

    manifest.exports = [ExtensionExport(capability: "speech", fields: ["model"])]
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidSchema)

    manifest.exports = [ExtensionExport(capability: "llm", fields: ["model", "displayName"])]
    #expect(ExtensionManifestValidator.validate(manifest) == nil)

    manifest.capabilities = []
    manifest.provides = []
    manifest.exports = []
    manifest.settings = ExtensionObjectSchema(
        properties: [
            "provider": ExtensionFieldSchema(type: "string", source: "llm"),
        ]
    )
    #expect(ExtensionManifestValidator.validate(manifest) == .invalidSchema)

    manifest.capabilities = ["llm"]
    #expect(ExtensionManifestValidator.validate(manifest) == nil)
}
