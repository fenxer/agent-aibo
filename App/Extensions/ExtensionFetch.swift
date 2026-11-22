import AiboCore
import Foundation

/// HTTPS fetch for `aibo/fetch`. Redirects are refused. The response body stops at 1 MB.
enum ExtensionFetch {
    static let byteLimit = 1_048_576
    static let requestBodyLimit = 12 * 1_048_576
    private static let allowedMethods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]
    private static let forbiddenHeaders: Set<String> = ["host", "cookie", "proxy-authorization"]

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(
            configuration: configuration,
            delegate: RedirectRefuser(),
            delegateQueue: nil
        )
    }()

    static func perform(
        params: [String: ExtensionValue],
        allowedHosts: Set<String>
    ) async -> [String: ExtensionValue] {
        guard let urlString = params["url"]?.stringValue else {
            return error("Missing URL")
        }
        if let reason = ExtensionURLPolicy.rejection(urlString: urlString, allowedHosts: allowedHosts) {
            return error(reason)
        }
        guard let url = URL(string: urlString) else {
            return error("invalid-url")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        let method = (params["method"]?.stringValue ?? "GET").uppercased()
        guard allowedMethods.contains(method) else {
            return error("Method not allowed")
        }
        request.httpMethod = method
        if let headers = params["headers"]?.objectValue {
            for (field, value) in headers {
                guard !forbiddenHeaders.contains(field.lowercased()) else { continue }
                if let text = value.stringValue {
                    request.setValue(text, forHTTPHeaderField: field)
                }
            }
        }
        if let body = params["body"]?.stringValue {
            let payload = Self.sendsJSON(params["headers"]?.objectValue, body: body)
                ? ExtensionPromptText.translatingJSONBody(body)
                : body
            let bodyData = Data(payload.utf8)
            guard bodyData.count <= requestBodyLimit else {
                return error("Request body too large")
            }
            request.httpBody = bodyData
        }
        do {
            let (bytes, response) = try await sharedSession.bytes(for: request)
            if let http = response as? HTTPURLResponse,
               http.expectedContentLength > Int64(byteLimit)
            {
                return error("Response exceeded 1 MB")
            }
            var data = Data()
            if let expected = (response as? HTTPURLResponse)?.expectedContentLength,
               expected > 0, expected <= Int64(byteLimit)
            {
                data.reserveCapacity(Int(expected))
            }
            for try await byte in bytes {
                if data.count >= byteLimit {
                    return error("Response exceeded 1 MB")
                }
                data.append(byte)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            return [
                "status": .number(Double(status)),
                "body": .string(body),
            ]
        } catch {
            return Self.error("Request failed")
        }
    }

    /// `JSON.stringify` leaves U+2028 / U+2029 raw. Only rewrite bodies that are JSON.
    private static func sendsJSON(_ headers: [String: ExtensionValue]?, body: String) -> Bool {
        if let headers {
            for (field, value) in headers {
                guard field.caseInsensitiveCompare("Content-Type") == .orderedSame,
                      let text = value.stringValue?.lowercased()
                else { continue }
                return text.contains("json")
            }
        }
        let trimmed = body.drop(while: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" })
        return trimmed.first == "{" || trimmed.first == "["
    }

    private static func error(_ message: String) -> [String: ExtensionValue] {
        ["error": .object(["message": .string(message)])]
    }
}

private final class RedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
