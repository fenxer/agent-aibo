import AiboCore
import Foundation
import Testing

struct SettingsProcessWireTests {
    @Test func roleParserDefaultsToMainAndRecognizesSettings() {
        #expect(SettingsProcessRole.parse(arguments: ["/Applications/aibo.app/Contents/MacOS/aibo"]) == .main)
        #expect(SettingsProcessRole.parse(arguments: ["aibo", "--role=settings"]) == .settings)
        #expect(SettingsProcessRole.parse(arguments: ["aibo", "--foo", "--role=settings", "--bar"]) == .settings)
        #expect(SettingsProcessRole.parse(arguments: ["aibo", "--role=unknown"]) == .main)
    }

    @Test func framingRoundTripsSingleAndChunkedMessages() throws {
        let first = Data("{\"hello\":\"world\"}".utf8)
        let second = Data(repeating: 0x41, count: 4096)
        let combined = try SettingsPipeFraming.encode(first) + SettingsPipeFraming.encode(second)

        var decoder = SettingsPipeFraming.Decoder()
        var decoded: [Data] = []
        // Feed 3 bytes at a time to exercise header/payload split across reads.
        var offset = 0
        while offset < combined.count {
            let end = min(offset + 3, combined.count)
            decoded.append(contentsOf: try decoder.append(combined[offset..<end]))
            offset = end
        }
        #expect(decoded == [first, second])
        #expect(!decoder.hasBufferedBytes)
    }

    @Test func framingRejectsOversizedPayloadOnEncodeAndDecode() throws {
        var decoder = SettingsPipeFraming.Decoder(maxPayloadBytes: 16)
        var header = UInt32(32).bigEndian
        let badHeader = withUnsafeBytes(of: &header) { Data($0) }
        #expect(throws: SettingsPipeFramingError.invalidFrameLength(32)) {
            _ = try decoder.append(badHeader)
        }

        let huge = Data(repeating: 0x01, count: SettingsPipeFraming.maxPayloadBytes + 1)
        #expect(throws: SettingsPipeFramingError.payloadTooLarge(huge.count)) {
            _ = try SettingsPipeFraming.encode(huge)
        }
    }

    @Test func wireMessagesRoundTripJSON() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let outgoing: MainToSettingsMessage = .show(
            destination: .backup(importArchivePath: "/tmp/test.aibobackup"),
            rememberedPaneID: "webhook"
        )
        let encodedOut = try encoder.encode(outgoing)
        #expect(try decoder.decode(MainToSettingsMessage.self, from: encodedOut) == outgoing)

        let incoming: SettingsToMainMessage = .library(.setScalePercent(percent: 150))
        let encodedIn = try encoder.encode(incoming)
        #expect(try decoder.decode(SettingsToMainMessage.self, from: encodedIn) == incoming)

        let snapshot = SettingsMainSnapshot(
            cursorHooksInstalled: true,
            webhookListening: true,
            tunnelHealthStatus: .ok,
            ingestLoggingEnabled: true,
            ingestLogEntryCount: 42,
            receiveLogEntries: [ReceiveLogEntry(source: "Webhook", message: "Deployed")],
            receiveLogTotalCount: 1,
            hasUpdateFeed: true,
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            availableUpdateDisplayVersion: "1.2.0",
            keystrokeAccessibilityTrusted: false
        )
        let snapMsg = MainToSettingsMessage.snapshot(snapshot)
        let snapData = try encoder.encode(snapMsg)
        #expect(try decoder.decode(MainToSettingsMessage.self, from: snapData) == snapMsg)
    }
}
