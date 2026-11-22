import AiboCore
import Darwin
import Foundation
import Synchronization

/// Bidirectional length-prefixed JSON pipe transport between main and settings processes.
///
/// - Uses non-blocking FDs with `DispatchSourceRead` / `DispatchSourceWrite` (zero polling,
///   0% idle CPU, and FDs are closed exclusively in each source's cancel handler so there is
///   never a cross-thread FD close/reuse race or stuck blocking syscall).
/// - Outbound buffer is bounded so a wedged peer cannot cause unbounded memory growth.
/// - `close()` shuts down both ends idempotently and notifies `onClose` at most once.
public final class SettingsPipeChannel: Sendable {
    private struct PendingWrite {
        var data: Data
        var offset: Int = 0
        var completion: (@Sendable (Bool) -> Void)?
    }

    private struct State {
        var readFD: Int32
        var writeFD: Int32
        var started = false
        var isClosed = false
        var didNotifyClose = false
    }

    private static let readBufferSize = 16 * 1024
    private static let maxPendingWriteBytes = 32 * 1024 * 1024

    private let state: Mutex<State>
    private let ioQueue = DispatchQueue(label: "work.fenx.aibo.settings-pipe.io", qos: .userInitiated)
    private let onFrame: @Sendable (Data) -> Void
    private let onClose: @Sendable () -> Void

    // Owned exclusively by `ioQueue` once `start()` runs.
    private nonisolated(unsafe) var readSource: DispatchSourceRead?
    private nonisolated(unsafe) var writeSource: DispatchSourceWrite?
    private nonisolated(unsafe) var writeSourceSuspended = true
    private nonisolated(unsafe) var decoder = SettingsPipeFraming.Decoder()
    private nonisolated(unsafe) var pendingWrites: [PendingWrite] = []
    private nonisolated(unsafe) var pendingWriteBytes = 0

    /// Takes ownership of `readFD` and `writeFD` and closes them on teardown.
    public init(
        readFD: Int32,
        writeFD: Int32,
        onFrame: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable () -> Void
    ) {
        signal(SIGPIPE, SIG_IGN)
        _ = Self.setCloseOnExec(readFD)
        _ = Self.setCloseOnExec(writeFD)
        _ = Self.setNonBlocking(readFD)
        _ = Self.setNonBlocking(writeFD)
        self.state = Mutex(State(readFD: readFD, writeFD: writeFD))
        self.onFrame = onFrame
        self.onClose = onClose
    }

    deinit {
        // If `start()` was never called, close descriptors that were never handed to DispatchSources.
        let unowned = state.withLock { state -> (Int32, Int32) in
            guard !state.started else { return (-1, -1) }
            let r = state.readFD
            let w = state.writeFD
            state.readFD = -1
            state.writeFD = -1
            state.isClosed = true
            return (r, w)
        }
        if unowned.0 >= 0 { Darwin.close(unowned.0) }
        if unowned.1 >= 0 { Darwin.close(unowned.1) }
    }

    public func start() {
        let fds = state.withLock { state -> (Int32, Int32)? in
            guard !state.started, !state.isClosed else { return nil }
            state.started = true
            let r = state.readFD
            let w = state.writeFD
            state.readFD = -1
            state.writeFD = -1
            return (r, w)
        }
        guard let (readFD, writeFD) = fds else {
            if state.withLock({ $0.isClosed }) {
                notifyClosedOnce()
            }
            return
        }

        ioQueue.async { [self] in
            if state.withLock({ $0.isClosed }) {
                if readFD >= 0 { Darwin.close(readFD) }
                if writeFD >= 0 { Darwin.close(writeFD) }
                failAllPendingWrites()
                notifyClosedOnce()
                return
            }

            if readFD >= 0 {
                let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: ioQueue)
                source.setEventHandler { [weak self] in
                    self?.drainReadable(fd: readFD)
                }
                source.setCancelHandler {
                    Darwin.close(readFD)
                }
                readSource = source
                source.resume()
            }

            if writeFD >= 0 {
                let source = DispatchSource.makeWriteSource(fileDescriptor: writeFD, queue: ioQueue)
                source.setEventHandler { [weak self] in
                    self?.drainWritable(fd: writeFD)
                }
                source.setCancelHandler {
                    Darwin.close(writeFD)
                }
                writeSource = source
                writeSourceSuspended = true
                if !pendingWrites.isEmpty {
                    resumeWriteSourceIfNeeded()
                }
            }
        }
    }

    public func send(_ payload: Data) {
        guard let framed = try? SettingsPipeFraming.encode(payload) else {
            close()
            return
        }
        enqueueWrite(framed, completion: nil)
    }

    public func send<Message: Encodable>(_ message: Message) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data)
    }

    /// Enqueues a payload and runs `completion` on the IO queue once flushed (or failed).
    public func send<Message: Encodable>(
        _ message: Message,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard let data = try? JSONEncoder().encode(message),
              let framed = try? SettingsPipeFraming.encode(data)
        else {
            completion(false)
            return
        }
        enqueueWrite(framed, completion: completion)
    }

    public func close() {
        let unowned = state.withLock { state -> (Int32, Int32) in
            state.isClosed = true
            guard !state.started else { return (-1, -1) }
            let r = state.readFD
            let w = state.writeFD
            state.readFD = -1
            state.writeFD = -1
            return (r, w)
        }
        if unowned.0 >= 0 { Darwin.close(unowned.0) }
        if unowned.1 >= 0 { Darwin.close(unowned.1) }

        ioQueue.async { [self] in
            tearDownSourcesOnIOQueue()
            notifyClosedOnce()
        }
    }

    /// Captures and isolates the child's inherited stdin/stdout for IPC before
    /// any framework can write stray logs to FD 1.
    public static func captureStandardIOForChild() -> (readFD: Int32, writeFD: Int32)? {
        signal(SIGPIPE, SIG_IGN)
        guard isFIFO(STDIN_FILENO), isFIFO(STDOUT_FILENO) else {
            return nil
        }
        let readFD = dup(STDIN_FILENO)
        let writeFD = dup(STDOUT_FILENO)
        guard readFD >= 0, writeFD >= 0 else {
            if readFD >= 0 { Darwin.close(readFD) }
            if writeFD >= 0 { Darwin.close(writeFD) }
            return nil
        }
        _ = setCloseOnExec(readFD)
        _ = setCloseOnExec(writeFD)

        // Route any stray stdout prints to stderr so binary framing stays clean.
        _ = dup2(STDERR_FILENO, STDOUT_FILENO)
        let devNull = open("/dev/null", O_RDONLY)
        if devNull >= 0 {
            _ = dup2(devNull, STDIN_FILENO)
            Darwin.close(devNull)
        }
        return (readFD, writeFD)
    }

    // MARK: - IO Queue Internals

    private func enqueueWrite(_ framed: Data, completion: (@Sendable (Bool) -> Void)?) {
        ioQueue.async { [self] in
            guard !state.withLock({ $0.isClosed }) else {
                completion?(false)
                return
            }
            if pendingWriteBytes + framed.count > Self.maxPendingWriteBytes {
                completion?(false)
                tearDownSourcesOnIOQueue()
                notifyClosedOnce()
                return
            }
            pendingWrites.append(PendingWrite(data: framed, completion: completion))
            pendingWriteBytes += framed.count
            resumeWriteSourceIfNeeded()
        }
    }

    private func drainReadable(fd: Int32) {
        guard !state.withLock({ $0.isClosed }) else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)

        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> ssize_t in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, raw.count)
            }
            if count > 0 {
                let chunk = Data(bytes: buffer, count: count)
                do {
                    let frames = try decoder.append(chunk)
                    for frame in frames {
                        onFrame(frame)
                    }
                } catch {
                    tearDownSourcesOnIOQueue()
                    notifyClosedOnce()
                    return
                }
            } else if count == 0 {
                tearDownSourcesOnIOQueue()
                notifyClosedOnce()
                return
            } else {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                tearDownSourcesOnIOQueue()
                notifyClosedOnce()
                return
            }
        }
    }

    private func drainWritable(fd: Int32) {
        guard !state.withLock({ $0.isClosed }) else { return }

        while !pendingWrites.isEmpty {
            var current = pendingWrites[0]
            let totalCount = current.data.count
            var blocked = false
            var failed = false

            current.data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                while current.offset < totalCount {
                    let remaining = totalCount - current.offset
                    let written = Darwin.write(fd, base.advanced(by: current.offset), remaining)
                    if written > 0 {
                        current.offset += written
                        pendingWriteBytes = max(0, pendingWriteBytes - written)
                    } else if written < 0, errno == EINTR {
                        continue
                    } else if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                        blocked = true
                        break
                    } else {
                        failed = true
                        break
                    }
                }
            }

            if failed {
                tearDownSourcesOnIOQueue()
                notifyClosedOnce()
                return
            }
            if blocked {
                pendingWrites[0] = current
                return
            }

            pendingWrites.removeFirst()
            current.completion?(true)
        }

        suspendWriteSourceIfNeeded()
    }

    private func resumeWriteSourceIfNeeded() {
        guard let writeSource, writeSourceSuspended else { return }
        writeSourceSuspended = false
        writeSource.resume()
    }

    private func suspendWriteSourceIfNeeded() {
        guard let writeSource, !writeSourceSuspended else { return }
        writeSourceSuspended = true
        writeSource.suspend()
    }

    private func tearDownSourcesOnIOQueue() {
        state.withLock { $0.isClosed = true }
        if let readSource {
            self.readSource = nil
            readSource.cancel()
        }
        if let writeSource {
            self.writeSource = nil
            if writeSourceSuspended {
                writeSourceSuspended = false
                writeSource.resume()
            }
            writeSource.cancel()
        }
        failAllPendingWrites()
    }

    private func failAllPendingWrites() {
        let dropped = pendingWrites
        pendingWrites.removeAll(keepingCapacity: false)
        pendingWriteBytes = 0
        for item in dropped {
            item.completion?(false)
        }
    }

    private func notifyClosedOnce() {
        let shouldNotify = state.withLock { state -> Bool in
            guard !state.didNotifyClose else { return false }
            state.didNotifyClose = true
            return true
        }
        if shouldNotify {
            onClose()
        }
    }

    private static func isFIFO(_ fd: Int32) -> Bool {
        var info = stat()
        guard fstat(fd, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFIFO
    }

    @discardableResult
    private static func setCloseOnExec(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFD)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0
    }

    @discardableResult
    private static func setNonBlocking(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
    }
}
