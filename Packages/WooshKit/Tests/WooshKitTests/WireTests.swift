import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import WooshKit

private final class TestSocket: WebSocketIO, @unchecked Sendable {
    let incoming = AsyncThrowingStream<Data, Error>.makeStream()
    let outgoing = AsyncStream<String>.makeStream()
    private let lock = NSLock()
    private var pongsRemaining: Int
    private let holdWrites: Bool

    init(pongs: Int = .max, holdWrites: Bool = false) {
        pongsRemaining = pongs
        self.holdWrites = holdWrites
    }

    func enqueue(_ frame: String, completion: @escaping @Sendable (Error?) -> Void) {
        outgoing.continuation.yield(frame)
        if !holdWrites { completion(nil) }
    }

    func read() async throws -> Data {
        var iterator = incoming.stream.makeAsyncIterator()
        guard let frame = try await iterator.next() else { throw TransportError.disconnected }
        return frame
    }

    func ping(_ completion: @escaping @Sendable (Error?) -> Void) {
        lock.lock()
        let sendPong = pongsRemaining > 0
        if sendPong { pongsRemaining -= 1 }
        lock.unlock()
        if sendPong { completion(nil) }
    }

    func close() {
        incoming.continuation.finish()
        outgoing.continuation.finish()
    }

    func push(_ text: String) {
        incoming.continuation.yield(Data(text.utf8))
    }
}

final class WireTests: XCTestCase {
    private let endpoint = Endpoint(host: "192.0.2.10")
    private let empty = Data("{}".utf8)

    private func object(_ frame: String?) throws -> [String: Any] {
        let text = try XCTUnwrap(frame)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testEndpointUsesOnlyIPAddressAndValidPort() {
        XCTAssertEqual(endpoint.url?.absoluteString, "ws://192.0.2.10:5480")
        XCTAssertEqual(Endpoint(host: "2001:db8::1", port: 1234).url?.absoluteString, "ws://[2001:db8::1]:1234")
        for host in ["", "192.0.2.256", "192.0.2.10/path", "user@192.0.2.10", "192.0.2.10\0more"] {
            XCTAssertFalse(Endpoint(host: host).isValid)
        }
        XCTAssertFalse(Endpoint(host: endpoint.host, port: 0).isValid)
        XCTAssertFalse(Endpoint(host: endpoint.host, port: 65536).isValid)
    }

    func testSubscriptionAndAuthenticationHandshake() async throws {
        let socket = TestSocket()
        let requests = AsyncStream<URLRequest>.makeStream()
        let transport = WebSocketTransport(credentials: { _ in BasicCredential(user: "test", password: "sample") }) {
            requests.continuation.yield($0)
            return socket
        }
        try await transport.connect(to: endpoint)
        var opened = requests.stream.makeAsyncIterator()
        let request = await opened.next()
        XCTAssertEqual(request?.url, endpoint.url)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("test:sample".utf8).base64EncodedString())

        let topics: Set<String> = ["woosh.robot.PoseSpeed", "woosh.robot.Battery"]
        var frames = socket.outgoing.stream.makeAsyncIterator()
        for enabled in [true, false] {
            try await transport.setSubscription(topics, enabled: enabled)
            let frame = try object(await frames.next())
            XCTAssertEqual(frame["type"] as? String, "woosh.Subscription")
            XCTAssertNil(frame["sn"])
            let body = try XCTUnwrap(frame["body"] as? [String: Any])
            XCTAssertEqual(body["sub"] as? Bool, enabled)
            XCTAssertEqual(body["topics"] as? [String], topics.sorted())
        }
        await transport.disconnect()
    }

    func testConcurrentRequestsMatchSequenceAndIgnoreMalformedFrames() async throws {
        let socket = TestSocket()
        let transport = WebSocketTransport { _ in socket }
        try await transport.connect(to: endpoint)
        var events = (await transport.events).makeAsyncIterator()
        var frames = socket.outgoing.stream.makeAsyncIterator()
        let type = "woosh.map.Download"
        let replyType = "woosh.map.DownloadResponse"
        let first = Task { try await transport.request(type: type, body: empty) }
        let firstFrame = try object(await frames.next())
        XCTAssertEqual(firstFrame["sn"] as? Int, 1)
        XCTAssertEqual(firstFrame["type"] as? String, type)
        XCTAssertEqual((firstFrame["body"] as? [String: Int])?.count, 0)

        let second = Task { try await transport.request(type: type, body: empty) }
        let secondFrame = try object(await frames.next())
        XCTAssertEqual(secondFrame["sn"] as? Int, 2)
        socket.push("broken")
        socket.push(#"{"type":"woosh.robot.RobotInfo","sn":1,"body":{}}"#)
        socket.push(#"{"type":"woosh.Subscription","ok":true,"body":{}}"#)
        socket.push(#"{"type":"woosh.map.DownloadResponse","sn":2,"ok":false,"msg":"robot message"}"#)
        socket.push(#"{"type":"woosh.robot.Battery","body":{"newField":"9223372036854775807"},"extra":1}"#)
        socket.push(#"{"type":"woosh.map.DownloadResponse","sn":1,"ok":true,"unknown":"ignored","body":{}}"#)
        let secondReply = try await second.value
        XCTAssertEqual(secondReply, Reply(type: replyType, body: empty, ok: false, message: "robot message"))
        let firstReply = try await first.value
        XCTAssertEqual(firstReply, Reply(type: replyType, body: empty, ok: true, message: ""))
        let event = await events.next()
        XCTAssertEqual(event, .notification(type: "woosh.robot.Battery",
                                           body: Data(#"{"newField":"9223372036854775807"}"#.utf8)))
        await transport.disconnect()
    }

    func testTraceContainsOnlyMatchingSerialAndRequestType() async throws {
        let trace = AsyncStream<String>.makeStream()
        let socket = TestSocket()
        let transport = WebSocketTransport(trace: { direction, sn, type in
            trace.continuation.yield("\(direction) \(sn) \(type)")
        }, makeSocket: { _ in socket })
        try await transport.connect(to: endpoint)
        var frames = socket.outgoing.stream.makeAsyncIterator()
        let type = Woosh_Robot_RobotWiFi.protoMessageName
        let sent = Task { try await transport.request(type: type, body: empty) }
        _ = await frames.next()
        socket.push(#"{"type":"woosh.robot.RobotWiFi","sn":1,"ok":false,"msg":"private failure detail"}"#)
        _ = try await sent.value
        var events = trace.stream.makeAsyncIterator()
        let first = await events.next()
        let second = await events.next()
        XCTAssertEqual(first, "request 1 \(type)")
        XCTAssertEqual(second, "rejected 1 \(type)")
        await transport.disconnect()
    }

    func testRequestTimeoutAndLateReplyKeepConnectionUsable() async throws {
        let socket = TestSocket()
        let transport = WebSocketTransport { _ in socket }
        try await transport.connect(to: endpoint)
        do {
            _ = try await transport.request(type: "woosh.robot.RobotInfo", body: empty, timeout: .milliseconds(15))
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? TransportError, .timeout)
        }
        socket.push(#"{"type":"woosh.robot.RobotInfo","sn":1,"ok":false,"msg":"late"}"#)
        let retry = Task { try await transport.request(type: "woosh.robot.RobotInfo", body: empty) }
        var frames = socket.outgoing.stream.makeAsyncIterator()
        _ = await frames.next()
        let request = try object(await frames.next())
        XCTAssertEqual(request["sn"] as? Int, 2)
        socket.push(#"{"type":"woosh.robot.RobotInfo","sn":2,"ok":true}"#)
        let reply = try await retry.value
        XCTAssertTrue(reply.ok)
        await transport.disconnect()
    }

    func testMissingPongReportsLossAndFailsPendingRequests() async throws {
        let socket = TestSocket(pongs: 1)
        let transport = WebSocketTransport(pingInterval: .milliseconds(20), pongTimeout: .milliseconds(15)) { _ in socket }
        try await transport.connect(to: endpoint)
        var events = (await transport.events).makeAsyncIterator()
        let request = Task { try await transport.request(type: "woosh.robot.RobotInfo", body: empty) }
        let event = await events.next()
        XCTAssertEqual(event, .stateChanged(.disconnected))
        do {
            _ = try await request.value
            XCTFail("Expected connection loss")
        } catch {
            XCTAssertEqual(error as? TransportError, .disconnected)
        }
        let end = await events.next()
        XCTAssertNil(end)
    }

    func testStopCanBeEnqueuedBeforePreviousWriteCompletes() async throws {
        let socket = TestSocket(holdWrites: true)
        let transport = WebSocketTransport { _ in socket }
        try await transport.connect(to: endpoint)
        var frames = socket.outgoing.stream.makeAsyncIterator()
        let type = "woosh.robot.Twist"
        let movement = Task { try await transport.sendCommand(type: type, body: Data(#"{"linear":0.1}"#.utf8)) }
        let first = try object(await frames.next())
        XCTAssertEqual((first["body"] as? [String: Double])?["linear"], 0.1)
        let stop = Task { try await transport.sendCommand(type: type, body: Data(#"{"linear":0}"#.utf8)) }
        let second = try object(await frames.next())
        XCTAssertEqual((second["body"] as? [String: Double])?["linear"], 0)
        await transport.disconnect()
        for task in [movement, stop] {
            do {
                try await task.value
                XCTFail("Expected pending socket writes to be released on close")
            } catch {
                XCTAssertEqual(error as? TransportError, .disconnected)
            }
        }
    }
}
