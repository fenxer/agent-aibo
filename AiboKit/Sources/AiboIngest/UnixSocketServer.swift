import AiboCore
import Darwin
import Foundation

/// NDJSON Unix-domain socket server for `aibo-hook` events.
///
/// One event-driven thread serves every client: it polls the listening socket
/// together with each accepted connection and dispatches a line the moment its
/// newline arrives. Hooks still write one line and close, but a client that
/// keeps its socket open can no longer delay anyone else — waiting for
/// end-of-stream here used to hold every agent's events until the stalled
/// client's process exited.
public final class UnixSocketServer: @unchecked Sendable {
    public enum ServerError: Error {
        case bindFailed(Int32)
        case listenFailed(Int32)
        case pathTooLong
    }

    /// A connection that sends nothing for this long is dropped. Hook clients
    /// write immediately, so this only ever fires for a wedged peer; closing it
    /// frees the descriptor instead of leaking it for the life of the app.
    public static let defaultIdleTimeout: TimeInterval = 30
    public static let maxConcurrentConnections = 64
    public static let maxBufferBytes = 2 * 1024 * 1024

    private static let readChunkSize = 4096
    private static let acceptBackoffMicroseconds: useconds_t = 50_000
    private static let newline = UInt8(ascii: "\n")

    /// Bytes read from one accepted connection, plus the deadline that ends it.
    private final class Connection {
        var buffer = Data()
        var deadline: Date

        init(deadline: Date) {
            self.buffer = Data()
            self.deadline = deadline
        }
    }

    private let path: String
    private let idleTimeout: TimeInterval
    private let queue = DispatchQueue(label: "work.fenx.aibo.unix-socket")
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var wakeReadFD: Int32 = -1
    private var wakeWriteFD: Int32 = -1
    private var socketInode: ino_t?
    private var isRunning = false

    public init(
        path: String = AiboPaths.socketURL.path,
        idleTimeout: TimeInterval = UnixSocketServer.defaultIdleTimeout
    ) {
        self.path = path
        self.idleTimeout = idleTimeout
    }

    public func start() throws -> AsyncStream<String> {
        stop()
        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.bindFailed(errno) }
        Self.configureDescriptor(fd)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathUTF8 = Array(path.utf8)
        guard pathUTF8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw ServerError.pathTooLong
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathUTF8.count + 1) { cPointer in
                for (index, byte) in pathUTF8.enumerated() {
                    cPointer[index] = CChar(bitPattern: byte)
                }
                cPointer[pathUTF8.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw ServerError.bindFailed(errno)
        }

        // Restrict socket permissions before accepting connections.
        chmod(path, S_IRUSR | S_IWUSR)

        var info = stat()
        let boundInode: ino_t? = stat(path, &info) == 0 ? info.st_ino : nil

        guard listen(fd, 32) == 0 else {
            close(fd)
            unlink(path)
            throw ServerError.listenFailed(errno)
        }

        var pipeFDs: [Int32] = [-1, -1]
        guard pipeFDs.withUnsafeMutableBufferPointer({ pipe($0.baseAddress) }) == 0 else {
            close(fd)
            unlink(path)
            throw ServerError.listenFailed(errno)
        }
        let wakeReader = pipeFDs[0]
        let wakeWriter = pipeFDs[1]
        Self.configureDescriptor(wakeReader)
        Self.configureDescriptor(wakeWriter)

        lock.lock()
        listenFD = fd
        wakeReadFD = wakeReader
        wakeWriteFD = wakeWriter
        socketInode = boundInode
        isRunning = true
        lock.unlock()

        return AsyncStream { continuation in
            queue.async { [weak self] in
                self?.acceptLoop(listener: fd, wakeReader: wakeReader, continuation: continuation)
            }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    /// Asks the accept loop to close the listener, its clients, and the socket
    /// file. Safe to call from any thread, and more than once.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false
        // The loop owns the descriptors; one byte through the wake pipe makes
        // its `poll` return so it can tear them down. Written under the lock so
        // it can never land on a descriptor the loop already closed.
        guard wakeWriteFD >= 0 else { return }
        var byte: UInt8 = 1
        _ = write(wakeWriteFD, &byte, 1)
    }

    private func isCurrentlyRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    private func markStopped() {
        lock.lock()
        isRunning = false
        lock.unlock()
    }

    private func acceptLoop(
        listener: Int32,
        wakeReader: Int32,
        continuation: AsyncStream<String>.Continuation
    ) {
        var connections: [Int32: Connection] = [:]
        var readChunk = [UInt8](repeating: 0, count: Self.readChunkSize)

        while isCurrentlyRunning() {
            var descriptors = [
                pollfd(fd: wakeReader, events: Int16(POLLIN), revents: 0),
                pollfd(fd: listener, events: Int16(POLLIN), revents: 0),
            ]
            for fd in connections.keys {
                descriptors.append(pollfd(fd: fd, events: Int16(POLLIN), revents: 0))
            }

            let ready = descriptors.withUnsafeMutableBufferPointer { buffer in
                poll(buffer.baseAddress, nfds_t(buffer.count), Self.pollTimeout(for: connections))
            }
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if !isCurrentlyRunning() { break }
            if descriptors[0].revents != 0 { break }
            if descriptors[1].revents != 0 {
                acceptPendingConnections(listener: listener, into: &connections)
            }
            for descriptor in descriptors.dropFirst(2) where descriptor.revents != 0 {
                readAvailableBytes(
                    on: descriptor.fd,
                    chunk: &readChunk,
                    connections: &connections,
                    continuation: continuation
                )
            }
            closeIdleConnections(&connections, continuation: continuation)
        }

        for fd in connections.keys {
            close(fd)
        }
        tearDown(expectedListener: listener)
        continuation.finish()
    }

    /// Milliseconds until the earliest connection deadline, or `-1` to sleep
    /// until a descriptor is ready. Idle servers block here and use no CPU.
    private static func pollTimeout(for connections: [Int32: Connection]) -> Int32 {
        guard let deadline = connections.values.map(\.deadline).min() else { return -1 }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return 0 }
        return Int32(min((remaining * 1000).rounded(.up), Double(Int32.max)))
    }

    private func acceptPendingConnections(
        listener: Int32,
        into connections: inout [Int32: Connection]
    ) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                let code = errno
                switch code {
                case EINTR, ECONNABORTED:
                    continue
                case EAGAIN, EWOULDBLOCK:
                    return
                case EBADF, EINVAL, ENOTSOCK:
                    // The listening socket is gone; retrying only fails again.
                    markStopped()
                    return
                default:
                    // Back off instead of spinning on an unknown accept error.
                    usleep(Self.acceptBackoffMicroseconds)
                    return
                }
            }
            if connections.count >= Self.maxConcurrentConnections {
                close(client)
                continue
            }
            Self.configureDescriptor(client)
            connections[client] = Connection(deadline: Date().addingTimeInterval(idleTimeout))
        }
    }

    private func readAvailableBytes(
        on fd: Int32,
        chunk: inout [UInt8],
        connections: inout [Int32: Connection],
        continuation: AsyncStream<String>.Continuation
    ) {
        guard let connection = connections[fd] else { return }

        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                if connection.buffer.count + count > Self.maxBufferBytes {
                    // Drop abusive/unterminated oversized stream to protect RAM.
                    connections.removeValue(forKey: fd)
                    close(fd)
                    return
                }
                connection.buffer.append(contentsOf: chunk[0..<count])
                connection.deadline = Date().addingTimeInterval(idleTimeout)
                Self.dispatchCompleteLines(from: &connection.buffer, continuation: continuation)
                continue
            }
            if count < 0 {
                let code = errno
                if code == EINTR { continue }
                if code == EAGAIN || code == EWOULDBLOCK { return }
            }

            // End of stream, or a broken socket: a final line that never got its
            // newline still counts, then the descriptor goes back to the kernel.
            Self.dispatchTrailingLine(from: &connection.buffer, continuation: continuation)
            connections.removeValue(forKey: fd)
            close(fd)
            return
        }
    }

    private func closeIdleConnections(
        _ connections: inout [Int32: Connection],
        continuation: AsyncStream<String>.Continuation
    ) {
        let now = Date()
        let expired = connections.filter { $0.value.deadline <= now }.map(\.key)
        for fd in expired {
            guard let connection = connections[fd] else { continue }
            Self.dispatchTrailingLine(from: &connection.buffer, continuation: continuation)
            connections.removeValue(forKey: fd)
            close(fd)
        }
    }

    private func tearDown(expectedListener: Int32) {
        lock.lock()
        let matchesCurrent = (listenFD == expectedListener)
        let listener: Int32
        let wakeReader: Int32
        let wakeWriter: Int32
        let expectedInode: ino_t?
        if matchesCurrent {
            isRunning = false
            listener = listenFD
            wakeReader = wakeReadFD
            wakeWriter = wakeWriteFD
            expectedInode = socketInode
            listenFD = -1
            wakeReadFD = -1
            wakeWriteFD = -1
            socketInode = nil
        } else {
            listener = -1
            wakeReader = -1
            wakeWriter = -1
            expectedInode = nil
        }
        lock.unlock()

        if listener >= 0 { close(listener) }
        if wakeReader >= 0 { close(wakeReader) }
        if wakeWriter >= 0 { close(wakeWriter) }

        if matchesCurrent {
            if let expectedInode {
                var current = stat()
                if stat(path, &current) == 0, current.st_ino == expectedInode {
                    unlink(path)
                }
            } else {
                unlink(path)
            }
        }
    }

    private static func configureDescriptor(_ fd: Int32) {
        let fl = fcntl(fd, F_GETFL)
        if fl >= 0 {
            _ = fcntl(fd, F_SETFL, fl | O_NONBLOCK)
        }
        let fdFlags = fcntl(fd, F_GETFD)
        if fdFlags >= 0 {
            _ = fcntl(fd, F_SETFD, fdFlags | FD_CLOEXEC)
        }
    }

    /// Dispatches every complete line and keeps a partial one buffered for the
    /// next read, so a line reaches the state machine without waiting for EOF.
    private static func dispatchCompleteLines(
        from buffer: inout Data,
        continuation: AsyncStream<String>.Continuation
    ) {
        var consumed = buffer.startIndex
        for index in buffer.indices where buffer[index] == newline {
            yield(buffer[consumed..<index], to: continuation)
            consumed = buffer.index(after: index)
        }
        guard consumed > buffer.startIndex else { return }
        if consumed == buffer.endIndex {
            buffer.removeAll(keepingCapacity: false)
        } else {
            buffer.removeSubrange(buffer.startIndex..<consumed)
        }
    }

    private static func dispatchTrailingLine(
        from buffer: inout Data,
        continuation: AsyncStream<String>.Continuation
    ) {
        guard !buffer.isEmpty else { return }
        yield(buffer[...], to: continuation)
        buffer.removeAll(keepingCapacity: false)
    }

    private static func yield(
        _ bytes: Data.SubSequence,
        to continuation: AsyncStream<String>.Continuation
    ) {
        guard !bytes.isEmpty, let line = String(data: Data(bytes), encoding: .utf8) else { return }
        continuation.yield(line)
    }
}
