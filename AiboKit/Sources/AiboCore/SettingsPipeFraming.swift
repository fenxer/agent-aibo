import Foundation

public enum SettingsPipeFramingError: Error, Equatable, Sendable {
    case payloadTooLarge(Int)
    case invalidFrameLength(Int)
}

/// Length-prefixed binary framing (`UInt32` big-endian length + UTF-8 JSON bytes)
/// for pipe IPC between the main process and the settings process.
public enum SettingsPipeFraming: Sendable {
    public static let headerByteCount = 4
    public static let maxPayloadBytes = 16 * 1024 * 1024

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxPayloadBytes else {
            throw SettingsPipeFramingError.payloadTooLarge(payload.count)
        }
        var length = UInt32(payload.count).bigEndian
        var framed = Data(capacity: headerByteCount + payload.count)
        withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
        framed.append(payload)
        return framed
    }

    public struct Decoder: Sendable {
        private var buffer = Data()
        private let maxPayloadBytes: Int

        public init(maxPayloadBytes: Int = SettingsPipeFraming.maxPayloadBytes) {
            self.maxPayloadBytes = maxPayloadBytes
        }

        public var hasBufferedBytes: Bool {
            !buffer.isEmpty
        }

        public mutating func append(_ chunk: Data) throws -> [Data] {
            guard !chunk.isEmpty else { return [] }
            buffer.append(chunk)

            var frames: [Data] = []
            while buffer.count >= SettingsPipeFraming.headerByteCount {
                let start = buffer.startIndex
                let b0 = UInt32(buffer[start])
                let b1 = UInt32(buffer[start + 1])
                let b2 = UInt32(buffer[start + 2])
                let b3 = UInt32(buffer[start + 3])
                let length = Int((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)

                guard length <= maxPayloadBytes else {
                    buffer.removeAll(keepingCapacity: false)
                    throw SettingsPipeFramingError.invalidFrameLength(length)
                }

                let frameSize = SettingsPipeFraming.headerByteCount + length
                guard buffer.count >= frameSize else { break }

                let payloadStart = start + SettingsPipeFraming.headerByteCount
                let payloadEnd = start + frameSize
                frames.append(Data(buffer[payloadStart..<payloadEnd]))
                buffer.removeSubrange(start..<payloadEnd)
            }
            return frames
        }
    }
}
