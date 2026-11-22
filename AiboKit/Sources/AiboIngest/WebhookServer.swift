import AiboCore
import Foundation
import Network
import Synchronization

/// Minimal loopback HTTP server for remote webhook POST delivery.
public final class WebhookServer: Sendable {
    public enum ServerError: Error {
        case invalidPort
        case listenerFailed
    }

    public static let maxConcurrentConnections = 32
    public static let connectionIdleTimeout: TimeInterval = 15
    public static let maxHeaderBytes = HTTPRequestParser.defaultMaxHeaderBytes
    public static let maxBodyBytes = HTTPRequestParser.defaultMaxBodyBytes

    public let port: UInt16

    public var isRunning: Bool {
        sharedState.withLock { $0.isRunning }
    }

    private struct SharedState {
        var isRunning = false
        var continuation: AsyncStream<WebhookDelivery>.Continuation?
    }

    private let secretProvider: @Sendable () -> String
    private let queue = DispatchQueue(label: "work.fenx.aibo.webhook")
    private let sharedState = Mutex(SharedState())

    // Owned exclusively by `queue`.
    private nonisolated(unsafe) var listener: NWListener?
    private nonisolated(unsafe) var idCache = WebhookIDCache()
    private nonisolated(unsafe) var activeConnections: [ObjectIdentifier: ActiveConnection] = [:]

    private final class ActiveConnection {
        let connection: NWConnection
        var timeoutItem: DispatchWorkItem?

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

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

        let newListener = try NWListener(using: parameters, on: nwPort)

        let stream = AsyncStream<WebhookDelivery> { continuation in
            sharedState.withLock { $0.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sharedState.withLock { $0.isRunning = true }
            case .failed, .cancelled:
                let continuation = self.sharedState.withLock { state -> AsyncStream<WebhookDelivery>.Continuation? in
                    state.isRunning = false
                    let current = state.continuation
                    state.continuation = nil
                    return current
                }
                continuation?.finish()
                self.cancelAllConnectionsOnQueue()
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleOnQueue(connection: connection)
        }

        queue.async { [self] in
            self.listener = newListener
            newListener.start(queue: self.queue)
        }
        return stream
    }

    public func stop() {
        let continuation = sharedState.withLock { state -> AsyncStream<WebhookDelivery>.Continuation? in
            state.isRunning = false
            let current = state.continuation
            state.continuation = nil
            return current
        }
        continuation?.finish()

        queue.async { [self] in
            self.listener?.cancel()
            self.listener = nil
            self.cancelAllConnectionsOnQueue()
        }
    }

    private func handleOnQueue(connection: NWConnection) {
        guard activeConnections.count < Self.maxConcurrentConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        let entry = ActiveConnection(connection: connection)
        activeConnections[id] = entry
        armIdleTimeout(for: entry, id: id)
        connection.start(queue: queue)
        receive(on: connection, id: id, buffer: Data())
    }

    private func armIdleTimeout(for entry: ActiveConnection, id: ObjectIdentifier) {
        entry.timeoutItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.closeConnectionOnQueue(id: id)
        }
        entry.timeoutItem = work
        queue.asyncAfter(deadline: .now() + Self.connectionIdleTimeout, execute: work)
    }

    private func closeConnectionOnQueue(id: ObjectIdentifier) {
        guard let entry = activeConnections.removeValue(forKey: id) else { return }
        entry.timeoutItem?.cancel()
        entry.timeoutItem = nil
        entry.connection.cancel()
    }

    private func cancelAllConnectionsOnQueue() {
        let entries = activeConnections.values
        activeConnections.removeAll()
        for entry in entries {
            entry.timeoutItem?.cancel()
            entry.timeoutItem = nil
            entry.connection.cancel()
        }
    }

    private func receive(on connection: NWConnection, id: ObjectIdentifier, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            guard let entry = self.activeConnections[id] else {
                connection.cancel()
                return
            }

            if error != nil {
                self.closeConnectionOnQueue(id: id)
                return
            }

            var next = buffer
            if let content {
                let maxTotal = Self.maxHeaderBytes + Self.maxBodyBytes + 4
                if next.count + content.count > maxTotal {
                    self.respond(.init(statusCode: 413), on: connection, id: id)
                    return
                }
                next.append(content)
            }

            self.armIdleTimeout(for: entry, id: id)

            do {
                let request = try HTTPRequestParser.parse(
                    next,
                    maxHeaderBytes: Self.maxHeaderBytes,
                    maxBodyBytes: Self.maxBodyBytes
                )
                let response = self.processOnQueue(request)
                self.respond(response, on: connection, id: id)
            } catch HTTPRequestParser.ParseError.incomplete {
                if isComplete {
                    self.respond(.init(statusCode: 400), on: connection, id: id)
                } else {
                    self.receive(on: connection, id: id, buffer: next)
                }
            } catch HTTPRequestParser.ParseError.payloadTooLarge {
                self.respond(.init(statusCode: 413), on: connection, id: id)
            } catch HTTPRequestParser.ParseError.unsupported {
                self.respond(.init(statusCode: 501), on: connection, id: id)
            } catch {
                self.respond(.init(statusCode: 400), on: connection, id: id)
            }
        }
    }

    private func processOnQueue(_ request: HTTPRequest) -> WebhookRequestHandler.Result {
        var cache = idCache
        let result = WebhookRequestHandler.handle(
            request: request,
            secret: secretProvider(),
            idCache: &cache
        )
        idCache = cache
        if let delivery = result.delivery {
            let continuation = sharedState.withLock { $0.continuation }
            continuation?.yield(delivery)
        }
        return result
    }

    private func respond(
        _ result: WebhookRequestHandler.Result,
        on connection: NWConnection,
        id: ObjectIdentifier
    ) {
        let reason: String = switch result.statusCode {
        case 200: "OK"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 501: "Not Implemented"
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
            completion: .contentProcessed { [weak self] _ in
                self?.closeConnectionOnQueue(id: id)
            }
        )
    }
}
