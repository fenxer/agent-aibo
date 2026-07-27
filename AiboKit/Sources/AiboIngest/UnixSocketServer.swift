import AiboCore
import Darwin
import Foundation

/// NDJSON Unix-domain socket server for `aibo-hook` events.
public final class UnixSocketServer: @unchecked Sendable {
    public enum ServerError: Error {
        case bindFailed(Int32)
        case listenFailed(Int32)
        case pathTooLong
    }

    private let path: String
    private let queue = DispatchQueue(label: "work.fenx.aibo.unix-socket")
    private var listenFD: Int32 = -1
    private var isRunning = false

    public init(path: String = AiboPaths.socketURL.path) {
        self.path = path
    }

    public func start() throws -> AsyncStream<String> {
        try HookQueue.ensureDirectories()
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.bindFailed(errno) }

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

        guard listen(fd, 32) == 0 else {
            close(fd)
            throw ServerError.listenFailed(errno)
        }

        // Restrict socket to the current user.
        chmod(path, S_IRUSR | S_IWUSR)

        listenFD = fd
        isRunning = true

        return AsyncStream { continuation in
            queue.async { [weak self] in
                self?.acceptLoop(continuation: continuation)
            }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    private func acceptLoop(continuation: AsyncStream<String>.Continuation) {
        while isRunning {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                let code = errno
                if !isRunning { break }
                switch code {
                case EINTR, ECONNABORTED:
                    continue
                case EBADF, EINVAL, ENOTSOCK:
                    break
                default:
                    usleep(50_000)
                    continue
                }
                break
            }
            defer { close(client) }
            for line in readLines(from: client) {
                continuation.yield(line)
            }
        }
        continuation.finish()
    }

    private func readLines(from fd: Int32) -> [String] {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
        }

        guard let text = String(data: buffer, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
