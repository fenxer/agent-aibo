import AiboCore
import Foundation
import Testing
@testable import AiboIngest

@Test func receiveLogAppendLoadClearAndExport() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-receive-log-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: temp) }

    let first = ReceiveLogEntry(
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
        source: "Webhook",
        message: "first",
        deliveryID: "d1"
    )
    let second = ReceiveLogEntry(
        receivedAt: Date(timeIntervalSince1970: 1_700_000_100),
        source: "Cursor",
        message: "second",
        deliveryID: "d2"
    )

    try ReceiveLogStore.append(first, url: temp)
    try ReceiveLogStore.append(second, url: temp)

    let loaded = try ReceiveLogStore.load(url: temp)
    #expect(loaded.count == 2)
    #expect(loaded[0].message == "second")
    #expect(loaded[1].source == "Webhook")
    #expect(try ReceiveLogStore.count(url: temp) == 2)

    let limited = try ReceiveLogStore.load(url: temp, limit: 1)
    #expect(limited.count == 1)
    #expect(limited[0].message == "second")

    let exported = try ReceiveLogStore.exportJSON(url: temp)
    let array = try JSONSerialization.jsonObject(with: exported) as? [[String: Any]]
    #expect(array?.count == 2)
    #expect(array?.first?["message"] as? String == "second")

    try ReceiveLogStore.clear(url: temp)
    #expect(try ReceiveLogStore.load(url: temp).isEmpty)
}
