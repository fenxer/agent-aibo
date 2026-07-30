import Foundation
import Testing
@testable import AiboIngest

@Test func hookQueueQueuedAtParsesEpochFilename() {
    let date = HookQueue.queuedAt(
        fromFilename: "1700000000.123456-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.json"
    )
    #expect(date == Date(timeIntervalSince1970: 1_700_000_000.123456))
    #expect(HookQueue.queuedAt(fromFilename: "not-a-queue-name.json") == nil)
    #expect(HookQueue.queuedAt(fromFilename: "abc-def.json") == nil)
}
