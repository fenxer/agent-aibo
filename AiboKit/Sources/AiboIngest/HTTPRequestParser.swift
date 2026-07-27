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
        for (key, value) in headers where key.lowercased() == target {
            return value
        }
        return nil
    }
}

public enum HTTPRequestParser {
    public enum ParseError: Error, Equatable {
        case incomplete
        case malformed
        case unsupported
    }

    /// Parses one HTTP/1.1 request. Returns `.incomplete` when more bytes are needed.
    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw ParseError.incomplete
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
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerRange.upperBound
        let contentLength: Int
        if let lengthValue = headers.first(where: { $0.key.lowercased() == "content-length" })?.value,
           let length = Int(lengthValue)
        {
            contentLength = length
        } else {
            contentLength = 0
        }
        guard contentLength >= 0 else { throw ParseError.malformed }

        let available = data.distance(from: bodyStart, to: data.endIndex)
        if available < contentLength {
            throw ParseError.incomplete
        }

        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        let body = data.subdata(in: bodyStart..<bodyEnd)
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
