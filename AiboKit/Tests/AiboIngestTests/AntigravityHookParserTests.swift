import AiboCore
import Foundation
import Testing
@testable import AiboIngest

@Test func antigravityPreToolUseReadsToolNameProjectAndModel() throws {
    let line = """
    {"aibo_agent":"antigravity","hook_event_name":"PreToolUse","conversationId":"conv-1","modelName":"gemini-3.6-flash-medium","workspacePaths":["/tmp/aibo"],"toolCall":{"name":"run_command","args":{"CommandLine":"true"}}}
    """
    let parsed = try HookLineParser.parse(jsonLine: line)
    #expect(parsed?.session == SessionKey(agent: .antigravity, conversationID: "conv-1"))
    #expect(parsed?.transition == .apply(.usingTool("run_command")))
    #expect(parsed?.projectName == "aibo")
    #expect(parsed?.modelName == "gemini-3.6-flash-medium")
    #expect(parsed?.eventName == "PreToolUse")
}

@Test func antigravityStopUsesTerminationReason() throws {
    let line = """
    {"aibo_agent":"antigravity","hook_event_name":"Stop","conversationId":"conv-1","terminationReason":"error","fullyIdle":true}
    """
    let parsed = try HookLineParser.parse(jsonLine: line)
    #expect(parsed?.transition == .apply(.failed))
}

@Test func antigravityPayloadWithoutStampIsNotCodex() throws {
    let line = """
    {"hook_event_name":"SessionStart","conversationId":"conv-1"}
    """
    let parsed = try HookLineParser.parse(jsonLine: line)
    #expect(parsed == nil)
}

@Test func antigravityHooksFileRefusesToOverwriteInvalidJSON() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-agy-hooks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("hooks.json")
    try Data("[]".utf8).write(to: url)

    #expect(throws: HooksInstallerError.invalidJSONObject) {
        try AntigravityHooksFile.install(binaryPath: "/tmp/aibo-hook", url: url)
    }
    let after = try Data(contentsOf: url)
    #expect(String(decoding: after, as: UTF8.self) == "[]")
}
