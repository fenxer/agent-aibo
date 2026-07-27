import AiboCore
import Foundation
import Network

/// Minimal loopback HTTP server for remote webhook POST delivery.
public final class WebhookServer: @unchecked Sendable {
    public enum ServerError: Error {
        case invalidPort
        case listenerFailed
    }

    public private(set) var port: UInt16
    public private(set) var isRunning = false

    private let secretProvider: @Sendable () -> String
    private let queue = DispatchQueue(label: "work.fenx.aibo.webhook")
    private var listener: NWListener?
    private var idCache = WebhookIDCache()
    private var continuation: AsyncStream<WebhookDelivery>.Continuation?

    public init(port: UInt16, secretProvider: @escaping @Sendable () -> String) {
        self.port = port
        self.secretProvider = secretProvider
    }

    public func start() throws -> AsyncStream<WebhookDelivery> {
        stop()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        let stream = AsyncStream<WebhookDelivery> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed, .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.start(queue: queue)
        return stream
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var next = buffer
            if let content {
                next.append(content)
            }

            if error != nil {
                connection.cancel()
                return
            }

            do {
                let request = try HTTPRequestParser.parse(next)
                let response = self.process(request)
                self.respond(response, on: connection)
            } catch HTTPRequestParser.ParseError.incomplete {
                if isComplete {
                    self.respond(.init(statusCode: 400), on: connection)
                } else {
                    self.receive(on: connection, buffer: next)
                }
            } catch {
                self.respond(.init(statusCode: 400), on: connection)
            }
        }
    }

    private func process(_ request: HTTPRequest) -> WebhookRequestHandler.Result {
        var cache = idCache
        let result = WebhookRequestHandler.handle(
            request: request,
            secret: secretProvider(),
            idCache: &cache
        )
        idCache = cache
        if let delivery = result.delivery {
            continuation?.yield(delivery)
        }
        return result
    }

    private func respond(_ result: WebhookRequestHandler.Result, on connection: NWConnection) {
        let reason: String = switch result.statusCode {
        case 200: "OK"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Bad Request"
        }
        let body = Data(reason.utf8)
        var response = Data()
        response.append(contentsOf: "HTTP/1.1 \(result.statusCode) \(reason)\r\n".utf8)
        response.append(contentsOf: "Content-Type: text/plain\r\n".utf8)
        response.append(contentsOf: "Content-Length: \(body.count)\r\n".utf8)
        response.append(contentsOf: "Connection: close\r\n\r\n".utf8)
        response.append(body)

        connection.send(
            content: response,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}
