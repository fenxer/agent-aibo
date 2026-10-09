import AiboCore
import Testing

@Test func dependencyGatePrefersEnabledThenDisabledThenCatalog() {
    let required = ["llm"]
    let installed = [
        ExtensionDependencyGate.Installed(
            id: "b",
            name: "Other",
            summary: "Also a model.",
            provides: ["llm"],
            enabled: false
        ),
        ExtensionDependencyGate.Installed(
            id: "a",
            name: "AI Provider",
            summary: "One place to configure a model API.",
            provides: ["llm"],
            enabled: false
        ),
    ]
    let catalog = [
        ExtensionDependencyGate.Listed(
            id: "dev.aibo.ai-provider",
            name: "AI Provider",
            summary: "From the catalog.",
            provides: ["llm"]
        ),
    ]

    let off = ExtensionDependencyGate.issues(required: required, installed: installed, catalog: catalog)
    #expect(off.count == 1)
    #expect(off.first?.remedy == .enable("a"))
    #expect(off.first?.name == "AI Provider")

    var enabled = installed
    enabled[1].enabled = true
    #expect(ExtensionDependencyGate.issues(required: required, installed: enabled, catalog: catalog).isEmpty)

    let missing = ExtensionDependencyGate.issues(required: required, installed: [], catalog: catalog)
    #expect(missing.first?.remedy == .install("dev.aibo.ai-provider"))
    #expect(missing.first?.summary == "From the catalog.")

    let nowhere = ExtensionDependencyGate.issues(required: required, installed: [], catalog: [])
    #expect(nowhere.first?.remedy == .unavailable)
    #expect(nowhere.first?.name == "llm")
}

@Test func dependencyGateKeepsEachMissingCapability() {
    let issues = ExtensionDependencyGate.issues(
        required: ["llm", "speech"],
        installed: [
            ExtensionDependencyGate.Installed(
                id: "voice",
                name: "Voice",
                summary: "Speaks.",
                provides: ["speech"],
                enabled: true
            ),
        ],
        catalog: []
    )
    #expect(issues.map(\.capability) == ["llm"])
}
