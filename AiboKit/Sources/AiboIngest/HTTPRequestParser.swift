import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        let target = name.lowercased()
        if let direct = headers[target] {
            return direct
        }
        for (key, value) in headers where key.lowercased() == target {
            return value
        }
        return nil
    }
}

public enum HTTPRequestParser {
    public static let defaultMaxHeaderBytes = 32 * 1024
    public static let defaultMaxBodyBytes = 1_048_576

    public enum ParseError: Error, Equatable {
        case incomplete
        case malformed
        case unsupported
        case payloadTooLarge
    }

    /// Parses one HTTP/1.1 request. Returns `.incomplete` when more bytes are needed.
    public static func parse(
        _ data: Data,
        maxHeaderBytes: Int = defaultMaxHeaderBytes,
        maxBodyBytes: Int = defaultMaxBodyBytes
    ) throws -> HTTPRequest {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maxHeaderBytes {
                throw ParseError.payloadTooLarge
            }
            throw ParseError.incomplete
        }

        let headerByteCount = data.distance(from: data.startIndex, to: headerRange.lowerBound)
        guard headerByteCount <= maxHeaderBytes else {
            throw ParseError.payloadTooLarge
        }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw ParseError.malformed
        }

        var lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let requestLine = lines.first else { throw ParseError.malformed }
        lines.removeFirst()

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { throw ParseError.malformed }
        let method = String(parts[0])
        let path = String(parts[1].split(separator: "?", maxSplits: 1).first ?? parts[1])

        var headers: [String: String] = [:]
        var contentLengthHeader: String?
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { throw ParseError.malformed }
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if name == "content-length" {
                if let existing = contentLengthHeader, existing != value {
                    throw ParseError.malformed
                }
                contentLengthHeader = value
            }
            headers[name] = value
        }

        if let transferEncoding = headers["transfer-encoding"],
           !transferEncoding.isEmpty
        {
            throw ParseError.unsupported
        }

        let bodyStart = headerRange.upperBound
        let contentLength: Int
        if let lengthValue = contentLengthHeader {
            guard !lengthValue.isEmpty,
                  lengthValue.allSatisfy(\.isASCII),
                  let length = Int(lengthValue),
                  length >= 0
            else {
                throw ParseError.malformed
            }
            guard length <= maxBodyBytes else {
                throw ParseError.payloadTooLarge
            }
            contentLength = length
        } else {
            contentLength = 0
        }

        let available = data.distance(from: bodyStart, to: data.endIndex)
        if available < contentLength {
            throw ParseError.incomplete
        }

        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        let body = data.subdata(in: bodyStart..<bodyEnd)
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
