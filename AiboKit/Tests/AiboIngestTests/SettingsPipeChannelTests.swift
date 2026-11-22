import AiboCore
import AiboIngest
import Darwin
import Foundation
import Synchronization
import Testing

struct SettingsPipeChannelTests {
    @Test func pipeChannelDeliversOrderedFramesAndClosesOnEOF() async throws {
        var pipeAtoB: [Int32] = [-1, -1]
        var pipeBtoA: [Int32] = [-1, -1]
        #expect(pipe(&pipeAtoB) == 0)
        #expect(pipe(&pipeBtoA) == 0)

        let received = Mutex<[SettingsToMainMessage]>([])
        let closed = Mutex<Bool>(false)

        let host = SettingsPipeChannel(
            readFD: pipeBtoA[0],
            writeFD: pipeAtoB[1],
            onFrame: { data in
                if let msg = try? JSONDecoder().decode(SettingsToMainMessage.self, from: data) {
                    received.withLock { $0.append(msg) }
                }
            },
            onClose: {
                closed.withLock { $0 = true }
            }
        )
        let client = SettingsPipeChannel(
            readFD: pipeAtoB[0],
            writeFD: pipeBtoA[1],
            onFrame: { _ in },
            onClose: {}
        )

        host.start()
        client.start()

        let expected: [SettingsToMainMessage] = [
            .ready(pid: 1234),
            .rememberPane(id: "aibo"),
            .library(.setScalePercent(percent: 125)),
            .closing,
        ]
        for message in expected {
            client.send(message)
        }

        // Wait until all 4 frames arrive in order.
        let deadline = ContinuousClock.now + .seconds(2)
        while received.withLock({ $0.count }) < expected.count && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(received.withLock { $0 } == expected)

        // Closing the client must trigger EOF and notify host onClose once.
        client.close()
        let closeDeadline = ContinuousClock.now + .seconds(2)
        while !closed.withLock({ $0 }) && ContinuousClock.now < closeDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(closed.withLock { $0 } == true)
        host.close()
    }

    @Test func launchedExecutableDetectsReplacementOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibo-exec-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("aibo")
        try Data("v1".utf8).write(to: file)

        let launched = LaunchedExecutable(executableURL: file)
        #expect(launched.matchesCurrentOnDisk())

        // Atomic replace creates a new inode.
        try Data("v2-updated".utf8).write(to: file, options: .atomic)
        #expect(!launched.matchesCurrentOnDisk())
    }
}
