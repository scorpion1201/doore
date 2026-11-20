import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct Endpoint: Hashable, Codable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int = 5480) {
        self.host = host
        self.port = port
    }

    public var isValid: Bool {
        guard (1...65535).contains(port), !host.utf8.contains(0) else { return false }
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return inet_pton(AF_INET, host, &ipv4) == 1 || inet_pton(AF_INET6, host, &ipv6) == 1
    }

    var url: URL? {
        guard isValid else { return nil }
        let authority = host.contains(":") ? "[\(host)]" : host
        return URL(string: "ws://\(authority):\(port)")
    }
}

public struct BasicCredential: Sendable {
    public let user: String
    public let password: String

    public init(user: String, password: String) {
        self.user = user
        self.password = password
    }
}

public enum ConnectionState: String, Sendable, Equatable {
    case disconnected, connecting, syncing, ready, reconnecting
}

public enum TransportError: Error, Sendable, Equatable {
    case invalidEndpoint, invalidEnvelope, disconnected, timeout
}

public struct Reply: Equatable, Sendable {
    public let type: String
    public let body: Data
    public let ok: Bool
    public let message: String

    public init(type: String, body: Data, ok: Bool, message: String) {
        self.type = type
        self.body = body
        self.ok = ok
        self.message = message
    }
}

public enum TransportEvent: Sendable, Equatable {
    case notification(type: String, body: Data)
    case stateChanged(ConnectionState)
}

public protocol RobotTransport: Sendable {
    func connect(to endpoint: Endpoint) async throws
    func disconnect() async
    func request(type: String, body: Data, timeout: Duration) async throws -> Reply
    /// Waits only for the socket write. The caller owns command cadence and coalescing.
    func sendCommand(type: String, body: Data) async throws
    func setSubscription(_ topics: Set<String>, enabled: Bool) async throws
    /// One buffered stream per connection. Obtain it after connecting, before subscribing.
    var events: AsyncStream<TransportEvent> { get async }
}
