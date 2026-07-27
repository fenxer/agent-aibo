import Testing
@testable import AiboCore

@Test func coreModuleNameIsStable() {
    #expect(AiboCore.moduleName == "AiboCore")
}
