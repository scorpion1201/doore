import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(OSLog)
import OSLog
#endif

/// JSON is inspected only at the envelope level. Protobuf payloads stay opaque to the transport.
enum PublicAPIEnvelope {
    // SceneData carries PNGs as Base64, so allow a larger frame than Foundation's default.
    static let maximumBytes = 64 * 1024 * 1024

    case reply(Int, Reply)
    case notification(String, Data)
    case unnumberedReply

    static func request(type: String, body: Data, sequence: Int) throws -> String {
        guard !type.isEmpty,
              let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw TransportError.invalidEnvelope
        }
        return try text(["type": type, "body": payload, "sn": sequence])
    }

    static func subscription(_ topics: Set<String>, enabled: Bool) throws -> String {
        // The public API calls this woosh.Subscription; the dedicated channel uses woosh.commu_pack.Subscription.
        try text(["type": "woosh.Subscription", "body": ["sub": enabled, "topics": topics.sorted()]])
    }

    private static func text(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private struct Header: Decodable {
        let type: String
        let sn: Int?
        let ok: Bool?
        let msg: String?
    }

    static func read(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw TransportError.invalidEnvelope }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard !header.type.isEmpty,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransportError.invalidEnvelope
        }
        // Some replies have no payload. A notification must contain its object.
        let payload: [String: Any]
        if let object = root["body"] as? [String: Any] {
            payload = object
        } else if root["body"] == nil, header.ok != nil {
            payload = [:]
        } else {
            throw TransportError.invalidEnvelope
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        if let ok = header.ok {
            guard let sequence = header.sn else { return .unnumberedReply }
            return .reply(sequence, Reply(type: header.type, body: body, ok: ok, message: header.msg ?? ""))
        }
        guard header.sn == nil else { throw TransportError.invalidEnvelope }
        return .notification(header.type, body)
    }
}

protocol WebSocketIO: Sendable {
    func enqueue(_ frame: String, completion: @escaping @Sendable (Error?) -> Void)
    func read() async throws -> Data
    func ping(_ completion: @escaping @Sendable (Error?) -> Void)
    func close()
}

private final class SystemWebSocket: NSObject, WebSocketIO, URLSessionTaskDelegate, @unchecked Sendable {
    // URLSession and URLSessionTask are thread-safe. These properties are set once before publication.
    private var session: URLSession!
    private var socket: URLSessionWebSocketTask!

    init(request: URLRequest) {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = PublicAPIEnvelope.maximumBytes
        socket.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func enqueue(_ frame: String, completion: @escaping @Sendable (Error?) -> Void) {
        socket.send(.string(frame), completionHandler: completion)
    }

    func read() async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): return Data(text.utf8)
        case .data(let data): return data
        @unknown default: throw TransportError.invalidEnvelope
        }
    }

    func ping(_ completion: @escaping @Sendable (Error?) -> Void) {
        socket.sendPing(pongReceiveHandler: completion)
    }

    func close() {
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

public actor WebSocketTransport: RobotTransport {
    /// Only the direction, sequence and locally selected request type reach the communication log.
    public typealias Trace = @Sendable (String, Int, String) -> Void
    private let trace: Trace
    private let makeSocket: @Sendable (URLRequest) -> any WebSocketIO
    private let credentials: @Sendable (Endpoint) -> BasicCredential?
    private let pingInterval: Duration
    private let pongTimeout: Duration

    public private(set) var events: AsyncStream<TransportEvent>
    private var eventSink: AsyncStream<TransportEvent>.Continuation
    private var socket: (any WebSocketIO)?
    private var generation = UUID()
    private var nextSequence = 1
    private var receiver: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var pongDeadline: Task<Void, Never>?
    private var pendingPong: CheckedContinuation<Void, Error>?

    private struct Pending {
        let type: String
        let continuation: CheckedContinuation<Reply, Error>
        let timer: Task<Void, Never>
    }

    private var pending = [Int: Pending]()

    private struct Write {
        let continuation: CheckedContinuation<Void, Error>
        let deadline: Task<Void, Never>
    }
    private var writes = [UUID: Write]()

    public init(credentials: @escaping @Sendable (Endpoint) -> BasicCredential? = { _ in nil },
                trace: @escaping Trace = { _, _, _ in }) {
        self.init(credentials: credentials, trace: trace, pingInterval: .seconds(15), pongTimeout: .seconds(10)) {
            SystemWebSocket(request: $0)
        }
    }

    init(credentials: @escaping @Sendable (Endpoint) -> BasicCredential? = { _ in nil },
         trace: @escaping Trace = { _, _, _ in },
         pingInterval: Duration = .seconds(15), pongTimeout: Duration = .seconds(10),
         makeSocket: @escaping @Sendable (URLRequest) -> any WebSocketIO) {
        self.credentials = credentials
        self.trace = trace
        self.makeSocket = makeSocket
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
        (events, eventSink) = AsyncStream.makeStream()
    }

    deinit {
        receiver?.cancel()
        heartbeat?.cancel()
        pongDeadline?.cancel()
        socket?.close()
        eventSink.finish()
    }

    public func connect(to endpoint: Endpoint) async throws {
        guard let url = endpoint.url else { throw TransportError.invalidEndpoint }
        close(reportLoss: false)
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        if let credential = credentials(endpoint) {
            let token = Data("\(credential.user):\(credential.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let opened = makeSocket(request)
        let id = generation
        socket = opened
        (events, eventSink) = AsyncStream.makeStream()
        do {
            // resume() only schedules the opening handshake. Wait for a pong before reporting success.
            try await withTaskCancellationHandler {
                try await ping(opened, generation: id)
            } onCancel: {
                Task { await self.cancelConnect(generation: id) }
            }
            try Task.checkCancellation()
            guard generation == id else { throw TransportError.disconnected }
        } catch {
            if generation == id { close(reportLoss: false) }
            throw error
        }
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let data = try await opened.read()
                    await self?.received(data, generation: id)
                }
            } catch {
                await self?.lostConnection(generation: id)
            }
        }
        heartbeat = Task { [weak self, pingInterval] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: pingInterval)
                    try await self?.ping(opened, generation: id)
                }
            } catch {
                await self?.lostConnection(generation: id)
            }
        }
    }

    public func disconnect() {
        close(reportLoss: false)
    }

    private func cancelConnect(generation id: UUID) {
        if generation == id { close(reportLoss: false) }
    }

    private func lostConnection(generation id: UUID) {
        if generation == id { close(reportLoss: true) }
    }

    private func close(reportLoss: Bool) {
        generation = UUID()
        receiver?.cancel()
        heartbeat?.cancel()
        receiver = nil
        heartbeat = nil
        completePong(.failure(TransportError.disconnected))
        for sequence in Array(pending.keys) { finish(sequence, result: .failure(TransportError.disconnected)) }
        for write in writes.values {
            write.deadline.cancel()
            write.continuation.resume(throwing: TransportError.disconnected)
        }
        writes.removeAll()
        socket?.close()
        socket = nil
        if reportLoss { eventSink.yield(.stateChanged(.disconnected)) }
        eventSink.finish()
    }

    private func ping(_ opened: any WebSocketIO, generation id: UUID) async throws {
        guard generation == id else { throw TransportError.disconnected }
        try await withCheckedThrowingContinuation { continuation in
            pendingPong = continuation
            pongDeadline = Task {
                do { try await Task.sleep(for: pongTimeout) } catch { return }
                if generation == id { completePong(.failure(TransportError.timeout)) }
            }
            opened.ping { error in
                Task { await self.pongReceived(error, generation: id) }
            }
        }
    }

    private func pongReceived(_ error: Error?, generation id: UUID) {
        guard generation == id else { return }
        if let error { completePong(.failure(error)) }
        else { completePong(.success(())) }
    }

    private func completePong(_ result: Result<Void, Error>) {
        pongDeadline?.cancel()
        pongDeadline = nil
        pendingPong?.resume(with: result)
        pendingPong = nil
    }

    public func request(type: String, body: Data, timeout: Duration = .seconds(30)) async throws -> Reply {
        guard let socket else { throw TransportError.disconnected }
        guard timeout > .zero else { throw TransportError.timeout }
        let sequence = allocateSequence()
        let frame = try PublicAPIEnvelope.request(type: type, body: body, sequence: sequence)
        let id = generation
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    finish(sequence, result: .failure(TransportError.timeout))
                }
                pending[sequence] = Pending(type: type, continuation: continuation, timer: timer)
                trace("request", sequence, type)
                socket.enqueue(frame) { error in
                    if error != nil { Task { await self.lostConnection(generation: id) } }
                }
            }
        } onCancel: {
            Task { await self.finish(sequence, result: .failure(CancellationError())) }
        }
    }

    public func sendCommand(type: String, body: Data) async throws {
        let sequence = allocateSequence()
        let frame = try PublicAPIEnvelope.request(type: type, body: body, sequence: sequence)
        trace("command", sequence, type)
        try await write(frame)
    }

    public func setSubscription(_ topics: Set<String>, enabled: Bool) async throws {
        try await write(PublicAPIEnvelope.subscription(topics, enabled: enabled))
    }

    private func write(_ frame: String) async throws {
        guard let socket else { throw TransportError.disconnected }
        try Task.checkCancellation()
        let id = generation
        let writeID = UUID()
        try await withCheckedThrowingContinuation { continuation in
            let deadline = Task {
                do { try await Task.sleep(for: pongTimeout) } catch { return }
                if writes[writeID] != nil { lostConnection(generation: id) }
            }
            writes[writeID] = Write(continuation: continuation, deadline: deadline)
            // Enqueue synchronously in actor order, including a stop while a previous write is in flight.
            socket.enqueue(frame) { error in
                Task { await self.written(writeID, error: error, generation: id) }
            }
        }
    }

    private func written(_ writeID: UUID, error: Error?, generation id: UUID) {
        guard generation == id, let write = writes.removeValue(forKey: writeID) else { return }
        write.deadline.cancel()
        if let error {
            write.continuation.resume(throwing: error)
            lostConnection(generation: id)
        } else {
            write.continuation.resume()
        }
    }

    private func allocateSequence() -> Int {
        defer { nextSequence += 1 }
        return nextSequence
    }

    private func finish(_ sequence: Int, result: Result<Reply, Error>) {
        guard let request = pending.removeValue(forKey: sequence) else { return }
        switch result {
        case .success(let reply): trace(reply.ok ? "reply" : "rejected", sequence, request.type)
        case .failure: trace("failed", sequence, request.type)
        }
        request.timer.cancel()
        request.continuation.resume(with: result)
    }

    private func received(_ data: Data, generation id: UUID) {
        guard generation == id else { return }
        do {
            switch try PublicAPIEnvelope.read(data) {
            case .reply(let sequence, let reply):
                // A request and its response can have different protobuf types. Only sn correlates them.
                finish(sequence, result: .success(reply))
            case .notification(let type, let body):
                eventSink.yield(.notification(type: type, body: body))
            case .unnumberedReply:
                break
            }
        } catch {
            #if canImport(OSLog)
            Logger(subsystem: "Doore", category: "WebSocket").error("Ignored malformed WebSocket envelope")
            #else
            NSLog("Ignored malformed WebSocket envelope")
            #endif
        }
    }
}
