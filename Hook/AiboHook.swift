import Darwin
import Foundation

// aibo-hook: read stdin → Unix socket (or queue) → exit 0 quickly.
// Must stay Foundation/Darwin only. Do not link AiboKit.

private let supportRelativePath = "Library/Application Support/aibo"
private let socketFileName = "aibo.sock"
private let queueDirectoryName = "queue"
private let maxQueueFiles = 200
private let maxQueueBytes = 5 * 1024 * 1024
private let maxStdinBytes = 2 * 1024 * 1024
private let socketDeadlineMs: Int32 = 500

@main
enum AiboHook {
    /// `aibo-hook antigravity <Event>`. Cursor and Codex invoke the binary with no arguments.
    private struct Invocation {
        var agent: String?
        var event: String?

        static func current() -> Invocation {
            let args = Array(CommandLine.arguments.dropFirst())
            return Invocation(agent: args.first, event: args.dropFirst().first)
        }

        var isAntigravity: Bool { agent == "antigravity" }
    }

    static func main() {
        let invocation = Invocation.current()
        let data = readBoundedStdin(maxBytes: maxStdinBytes)
        if !data.isEmpty, let line = line(from: data, invocation: invocation) {
            let home = NSHomeDirectory()
            let support = (home as NSString).appendingPathComponent(supportRelativePath)
            let socketPath = (support as NSString).appendingPathComponent(socketFileName)
            if !send(line: line, to: socketPath) {
                let queue = (support as NSString).appendingPathComponent(queueDirectoryName)
                enqueue(line: line, support: support, queue: queue)
            }
        }
        writeStdout(for: invocation)
    }

    private static func readBoundedStdin(maxBytes: Int) -> Data {
        var collected = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while collected.count < maxBytes {
            let remaining = maxBytes - collected.count
            let toRead = min(chunk.count, remaining)
            let count = chunk.withUnsafeMutableBytes { raw -> ssize_t in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(STDIN_FILENO, base, toRead)
            }
            if count > 0 {
                collected.append(contentsOf: chunk[0..<count])
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }
        return collected
    }

    /// Antigravity's payload has no event name. Stamp it before the socket write.
    /// Multi-line JSON from other agents is compacted to a single NDJSON line.
    /// A payload that is not a JSON object is dropped; stdout still follows the
    /// event contract so a bad line cannot deny a tool.
    private static func line(from data: Data, invocation: Invocation) -> Data? {
        if invocation.isAntigravity {
            return stampAntigravity(data, event: invocation.event)
        }
        var trimmed = data
        while let last = trimmed.last, last == UInt8(ascii: "\n") || last == UInt8(ascii: "\r") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return nil }

        // Fast path: already single-line NDJSON — forward raw bytes with zero JSON parsing.
        if !trimmed.contains(UInt8(ascii: "\n")) && !trimmed.contains(UInt8(ascii: "\r")) {
            trimmed.append(UInt8(ascii: "\n"))
            return trimmed
        }

        // Slow path: pretty-printed multi-line JSON — compact to one line so NDJSON framing stays intact.
        guard let object = try? JSONSerialization.jsonObject(with: trimmed),
              var compacted = try? JSONSerialization.data(withJSONObject: object)
        else {
            return nil
        }
        compacted.append(UInt8(ascii: "\n"))
        return compacted
    }

    private static func stampAntigravity(_ data: Data, event: String?) -> Data? {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        object["aibo_agent"] = "antigravity"
        if let event, !event.isEmpty {
            object["hook_event_name"] = event
        }
        guard var stamped = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        stamped.append(UInt8(ascii: "\n"))
        return stamped
    }

    /// Cursor and Codex stay fail-open with `permission: allow`.
    /// Antigravity `PreToolUse` must print nothing: a JSON object without
    /// `decision` is treated as deny and would override Auto.
    /// `PostToolUse` and `Stop` want `{}`. `Stop` must not say `continue`.
    private static func writeStdout(for invocation: Invocation) {
        if !invocation.isAntigravity {
            writeAllowJSON()
            return
        }
        switch invocation.event {
        case "PostToolUse", "Stop":
            if let data = "{}".data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
        default:
            break
        }
    }

    private static func writeAllowJSON() {
        if let data = #"{"permission":"allow"}"#.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }

    private static func send(line: Data, to socketPath: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathUTF8 = Array(socketPath.utf8)
        guard pathUTF8.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathUTF8.count + 1) { cPointer in
                for (index, byte) in pathUTF8.enumerated() {
                    cPointer[index] = CChar(bitPattern: byte)
                }
                cPointer[pathUTF8.count] = 0
            }
        }

        let deadline = Date().addingTimeInterval(TimeInterval(socketDeadlineMs) / 1000.0)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN else { return false }
            guard waitWritable(fd: fd, until: deadline) else { return false }
            var soError: Int32 = 0
            var soErrorLen = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &soErrorLen) == 0,
                  soError == 0
            else {
                return false
            }
        }

        return writeAll(line, to: fd, until: deadline)
    }

    private static func waitWritable(fd: Int32, until deadline: Date) -> Bool {
        while true {
            let remainingMs = Int32(ceil(deadline.timeIntervalSinceNow * 1000.0))
            guard remainingMs > 0 else { return false }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&pfd, 1, remainingMs)
            if ready > 0 {
                return (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0
            }
            if ready < 0, errno == EINTR { continue }
            return false
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32, until deadline: Date) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return false }
            var offset = 0
            let total = rawBuffer.count
            while offset < total {
                let written = write(fd, base.advanced(by: offset), total - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    guard waitWritable(fd: fd, until: deadline) else { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func enqueue(line: Data, support: String, queue: String) {
        guard line.count <= maxQueueBytes else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: support, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: queue, withIntermediateDirectories: true)
        trimQueue(at: queue, reservingBytes: line.count)

        let id = UUID().uuidString
        let name = String(format: "%.6f-%@.json", Date().timeIntervalSince1970, id)
        let finalPath = (queue as NSString).appendingPathComponent(name)
        let tempPath = (queue as NSString).appendingPathComponent(".tmp-\(id)")
        // Write to a hidden temp file then rename so a concurrent `HookQueue.drain()` never sees partial JSON.
        guard fileManager.createFile(atPath: tempPath, contents: line) else { return }
        if rename(tempPath, finalPath) != 0 {
            try? fileManager.removeItem(atPath: tempPath)
        }
    }

    private static func trimQueue(at queue: String, reservingBytes incomingBytes: Int) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: queue) else { return }
        let files = names
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }
            .sorted()
            .map { (queue as NSString).appendingPathComponent($0) }

        var total = incomingBytes
        var sizes: [String: Int] = [:]
        for path in files {
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            sizes[path] = size
            total += size
        }

        var mutable = files
        while mutable.count >= maxQueueFiles || total > maxQueueBytes {
            guard let oldest = mutable.first else { break }
            total -= sizes[oldest] ?? 0
            try? fileManager.removeItem(atPath: oldest)
            mutable.removeFirst()
        }
    }
}
