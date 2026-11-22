import Darwin
import Foundation

// aibo-hook: read stdin → Unix socket (or queue) → exit 0 quickly.
// Must stay Foundation/Darwin only. Do not link AiboKit.

private let supportRelativePath = "Library/Application Support/aibo"
private let socketFileName = "aibo.sock"
private let queueDirectoryName = "queue"
private let maxQueueFiles = 200
private let maxQueueBytes = 5 * 1024 * 1024

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
        let data = FileHandle.standardInput.readDataToEndOfFile()
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

    /// Antigravity's payload has no event name. Stamp it before the socket write.
    /// A payload that is not a JSON object is dropped; stdout still follows the
    /// event contract so a bad line cannot deny a tool.
    private static func line(from data: Data, invocation: Invocation) -> Data? {
        if invocation.isAntigravity {
            return stampAntigravity(data, event: invocation.event)
        }
        var line = data
        if line.last != UInt8(ascii: "\n") {
            line.append(UInt8(ascii: "\n"))
        }
        return line
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

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        return writeAll(line, to: fd)
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return false }
            var offset = 0
            let total = rawBuffer.count
            while offset < total {
                let written = write(fd, base.advanced(by: offset), total - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    private static func enqueue(line: Data, support: String, queue: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: support, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: queue, withIntermediateDirectories: true)
        trimQueue(at: queue)

        let name = String(format: "%.6f-%@.json", Date().timeIntervalSince1970, UUID().uuidString)
        let path = (queue as NSString).appendingPathComponent(name)
        fileManager.createFile(atPath: path, contents: line)
    }

    private static func trimQueue(at queue: String) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: queue) else { return }
        let files = names
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { (queue as NSString).appendingPathComponent($0) }

        var total = 0
        var sizes: [String: Int] = [:]
        for path in files {
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            sizes[path] = size
            total += size
        }

        var mutable = files
        while mutable.count > maxQueueFiles || total > maxQueueBytes {
            guard let oldest = mutable.first else { break }
            total -= sizes[oldest] ?? 0
            try? fileManager.removeItem(atPath: oldest)
            mutable.removeFirst()
        }
    }
}
