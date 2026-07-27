import Testing
@testable import AiboIngest

@Test func ingestDependsOnCore() {
    #expect(AiboIngest.moduleName == "AiboIngest")
    #expect(AiboIngest.coreModuleName == "AiboCore")
}
