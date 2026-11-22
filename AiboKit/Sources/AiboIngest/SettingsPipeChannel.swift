import AiboCore
import Darwin
import Foundation
import Synchronization

/// Bidirectional length-prefixed JSON pipe transport between main and settings processes.
///
/// - Reading blocks on a dedicated queue (zero polling, 0% idle CPU).
/// - Writing is serialized on a separate queue so a slow or dead peer never blocks the caller.
/// - `close()` shuts down both ends idempotently and notifies `onClose` at most once.
public final class SettingsPipeChannel: Sendable {
    private struct State {
        var readFD: Int32
        var writeFD: Int32
        var isClosed = false
        var didNotifyClose = false
    }

    private static let readBufferSize = 16 * 1024

    private let state: Mutex<State>
    private let readQueue = DispatchQueue(label: "work.fenx.aibo.settings-pipe.read", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "work.fenx.aibo.settings-pipe.write", qos: .userInitiated)
    private let onFrame: @Sendable (Data) -> Void
    private let onClose: @Sendable () -> Void

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
        self.state = Mutex(State(readFD: readFD, writeFD: writeFD))
        self.onFrame = onFrame
        self.onClose = onClose
    }

    deinit {
        closeDescriptors()
    }

    public func start() {
        let fd = state.withLock { $0.isClosed ? -1 : $0.readFD }
        guard fd >= 0 else {
            notifyClosedOnce()
            return
        }
        readQueue.async { [weak self] in
            self?.runReadLoop(fd: fd)
        }
    }

    public func send(_ payload: Data) {
        guard let framed = try? SettingsPipeFraming.encode(payload) else {
            close()
            return
        }
        writeQueue.async { [weak self] in
            self?.writeAll(framed)
        }
    }

    public func send<Message: Encodable>(_ message: Message) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data)
    }

    /// Enqueues a payload and runs `completion` on the write queue once flushed (or failed).
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
        writeQueue.async { [weak self] in
            let ok = self?.writeAll(framed) ?? false
            completion(ok)
        }
    }

    public func close() {
        closeDescriptors()
        notifyClosedOnce()
    }

    /// Captures and isolates the child's inherited stdin/stdout for IPC before
    /// any framework can write stray logs to FD 1.
    public static func captureStandardIOForChild() -> (readFD: Int32, writeFD: Int32)? {
        signal(SIGPIPE, SIG_IGN)
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

    private func runReadLoop(fd: Int32) {
        var decoder = SettingsPipeFraming.Decoder()
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
                    break
                }
            } else if count == 0 {
                break
            } else {
                if errno == EINTR { continue }
                break
            }
        }

        closeDescriptors()
        notifyClosedOnce()
    }

    @discardableResult
    private func writeAll(_ data: Data) -> Bool {
        let fd = state.withLock { $0.isClosed ? -1 : $0.writeFD }
        guard fd >= 0 else { return false }

        var writtenTotal = 0
        let totalCount = data.count
        let succeeded = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            while writtenTotal < totalCount {
                let remaining = totalCount - writtenTotal
                let written = Darwin.write(fd, base.advanced(by: writtenTotal), remaining)
                if written > 0 {
                    writtenTotal += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        if !succeeded {
            close()
        }
        return succeeded
    }

    private func closeDescriptors() {
        let fds = state.withLock { state -> (Int32, Int32) in
            let readFD = state.readFD
            let writeFD = state.writeFD
            state.readFD = -1
            state.writeFD = -1
            state.isClosed = true
            return (readFD, writeFD)
        }
        if fds.0 >= 0 { Darwin.close(fds.0) }
        if fds.1 >= 0 { Darwin.close(fds.1) }
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

    @discardableResult
    private static func setCloseOnExec(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFD)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0
    }
}
