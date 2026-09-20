import Darwin
import Foundation
import Testing
@testable import AiboIngest

// The server must hand a line to the state machine the moment it arrives. The
// regression these tests pin down: waiting for end-of-stream made every bubble
// wait for the agent process to exit, and one client that never closed its
// socket stalled ingest for the whole app.

private enum SocketTestError: Error {
    case socket(Int32)
    case connect(Int32)
    case timedOut([String])
}

/// Collects stream output so a test can assert on it without hanging forever.
private final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func waitForCount(_ count: Int, timeout: Duration = .seconds(2)) async throws -> [String] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let current = lines
            if current.count >= count { return current }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SocketTestError.timedOut(lines)
    }
}

private struct TestServer {
    let server: UnixSocketServer
    let sink: LineSink
    let path: String
}

private func startTestServer(idleTimeout: TimeInterval = 5) throws -> TestServer {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-socket-\(UUID().uuidString).sock")
        .path
    let server = UnixSocketServer(path: path, idleTimeout: idleTimeout)
    let stream = try server.start()
    let sink = LineSink()
    Task.detached {
        for await line in stream {
            sink.append(line)
        }
    }
    return TestServer(server: server, sink: sink, path: path)
}

private func connectTestClient(to path: String, receiveTimeout: TimeInterval? = nil) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw SocketTestError.socket(errno) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathUTF8 = Array(path.utf8)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathUTF8.count + 1) { cPointer in
            for (index, byte) in pathUTF8.enumerated() {
                cPointer[index] = CChar(bitPattern: byte)
            }
            cPointer[pathUTF8.count] = 0
        }
    }
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else {
        let code = errno
        close(fd)
        throw SocketTestError.connect(code)
    }

    if let receiveTimeout {
        var timeout = timeval(
            tv_sec: Int(receiveTimeout),
            tv_usec: suseconds_t((receiveTimeout - Double(Int(receiveTimeout))) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    return fd
}

private func writeTestClient(_ text: String, to fd: Int32) throws {
    let bytes = Array(text.utf8)
    var offset = 0
    while offset < bytes.count {
        let written = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return write(fd, base.advanced(by: offset), bytes.count - offset)
        }
        guard written > 0 else { throw SocketTestError.socket(errno) }
        offset += written
    }
}

private func readTestByte(from fd: Int32) -> Int {
    var byte: UInt8 = 0
    return read(fd, &byte, 1)
}

@Test func unixSocketServerDispatchesALineBeforeTheClientCloses() async throws {
    let test = try startTestServer()
    defer { test.server.stop() }

    let client = try connectTestClient(to: test.path)
    defer { close(client) }
    try writeTestClient("{\"hook_event_name\":\"PreToolUse\"}\n", to: client)

    let lines = try await test.sink.waitForCount(1)
    #expect(lines == ["{\"hook_event_name\":\"PreToolUse\"}"])
}

@Test func unixSocketServerFramesALineSplitAcrossWrites() async throws {
    let test = try startTestServer()
    defer { test.server.stop() }

    let client = try connectTestClient(to: test.path)
    defer { close(client) }
    try writeTestClient("{\"hook_event_", to: client)
    try writeTestClient("name\":\"Stop\"}\n", to: client)

    let lines = try await test.sink.waitForCount(1)
    #expect(lines == ["{\"hook_event_name\":\"Stop\"}"])
}

@Test func unixSocketServerDispatchesEveryLineOfOneWriteInOrder() async throws {
    let test = try startTestServer()
    defer { test.server.stop() }

    let client = try connectTestClient(to: test.path)
    defer { close(client) }
    try writeTestClient("first\nsecond\n", to: client)

    let lines = try await test.sink.waitForCount(2)
    #expect(lines == ["first", "second"])
}

@Test func unixSocketServerSilentClientDoesNotHoldUpAnotherClient() async throws {
    let test = try startTestServer()
    defer { test.server.stop() }

    let silent = try connectTestClient(to: test.path)
    defer { close(silent) }
    let talker = try connectTestClient(to: test.path)
    defer { close(talker) }
    try writeTestClient("{\"hook_event_name\":\"SessionStart\"}\n", to: talker)

    let lines = try await test.sink.waitForCount(1)
    #expect(lines == ["{\"hook_event_name\":\"SessionStart\"}"])
}

@Test func unixSocketServerClosesAClientThatStopsSending() async throws {
    let test = try startTestServer(idleTimeout: 0.2)
    defer { test.server.stop() }

    let client = try connectTestClient(to: test.path, receiveTimeout: 2)
    defer { close(client) }
    try writeTestClient("{\"hook_event_name\":\"PreToolUse\"}\n", to: client)
    _ = try await test.sink.waitForCount(1)

    // The line is dispatched first; the silent connection is then dropped.
    #expect(readTestByte(from: client) == 0)
}

@Test func unixSocketServerDispatchesATrailingLineWithoutNewlineOnClose() async throws {
    let test = try startTestServer()
    defer { test.server.stop() }

    let client = try connectTestClient(to: test.path)
    try writeTestClient("{\"hook_event_name\":\"Stop\"}", to: client)
    close(client)

    let lines = try await test.sink.waitForCount(1)
    #expect(lines == ["{\"hook_event_name\":\"Stop\"}"])
}

@Test func unixSocketServerStopRemovesTheSocketFile() async throws {
    let test = try startTestServer()
    test.server.stop()

    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while FileManager.default.fileExists(atPath: test.path), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(FileManager.default.fileExists(atPath: test.path) == false)
}
