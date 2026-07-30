import AiboCore
import Foundation
import Testing
@testable import AiboIngest

@Test func ingestLogAppendLoadClearAndExportJSONL() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-ingest-log-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: temp) }

    let first = IngestLogEntry(
        at: Date(timeIntervalSince1970: 1_700_000_000),
        kind: "drain",
        outcome: "summary",
        detail: "count=1"
    )
    let second = IngestLogEntry(
        at: Date(timeIntervalSince1970: 1_700_000_100),
        kind: "event",
        source: "queue",
        queuedAt: Date(timeIntervalSince1970: 1_699_999_000),
        eventName: "beforeSubmitPrompt",
        agent: "cursor",
        conversationID: "abc",
        projectName: "aibo",
        isSubagent: false,
        activity: "thinking",
        outcome: "applied",
        activeSessionCount: 1
    )

    try IngestLogStore.append(first, url: temp)
    try IngestLogStore.append(second, url: temp)

    let loaded = try IngestLogStore.load(url: temp)
    #expect(loaded.count == 2)
    #expect(loaded[0].eventName == "beforeSubmitPrompt")
    #expect(loaded[0].source == "queue")
    #expect(loaded[1].kind == "drain")
    #expect(try IngestLogStore.count(url: temp) == 2)

    let raw = try IngestLogStore.exportJSONL(url: temp)
    let text = String(data: raw, encoding: .utf8) ?? ""
    #expect(text.contains("beforeSubmitPrompt"))
    #expect(text.contains("\"kind\":\"drain\""))

    try IngestLogStore.clear(url: temp)
    #expect(try IngestLogStore.load(url: temp).isEmpty)
}
