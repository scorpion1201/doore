import Foundation
import WooshKit

/// An in-memory robot. Faults and task progress advance only when the test asks.
public actor FakeRobotTransport: RobotTransport {
    public enum Call: Equatable, Sendable {
        case connect
        case subscription(Set<String>, enabled: Bool)
        case request(type: String, body: Data)
        case command(type: String, body: Data)
    }

    public enum Response: Sendable {
        case success(Data)
        case delayed(Data, by: Duration)
        case rejected(String)
        case timeout
    }

    public private(set) var events: AsyncStream<TransportEvent>
    public private(set) var calls: [Call] = []
    private var continuation: AsyncStream<TransportEvent>.Continuation
    private var connected = false
    private var topics: Set<String> = []
    private var failuresBeforeConnect = 0
    private var queued: [String: [Response]] = [:]
    private let snapshots: [String: Data]

    public init(snapshots: [String: Data] = FakeRobotTransport.exampleSnapshots) {
        self.snapshots = snapshots
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
    }

    // A synthetic floor with two shelving blocks, expressed in the public API's JSON mapping.
    public static let exampleSnapshots: [String: Data] = [
        Woosh_Map_SceneList.protoMessageName: Data(#"{"scenes":[{"name":"예시","maps":["F1"]}]}"#.utf8),
        RobotFeed.robotInfo.rawValue: Data("""
            {
              "robotId":1, "genral":{"serialNumber":1},
              "setting":{"identity":{"name":"예시-01"}},
              "state":2, "mode":{"ctrl":1,"work":2},
              "battery":{"power":82,"chargeState":1}, "deviceState":{"hardware":0},
              "network":{"robotIp":"192.0.2.1","wifi":{"strength":80}},
              "scene":{"sceneName":"예시","mapId":1,"mapName":"F1"},
              "poseSpeed":{"mapId":1,"pose":{"x":3.5,"y":2.0,"theta":0}}
            }
            """.utf8),
        RobotFeed.sceneData.rawValue: Data("""
            {
              "name":"예시",
              "maps":[{
                "id":1, "name":"F1", "resolution":0.1, "origin":{}, "end":{"x":8,"y":4.8},
                "mapPng":"iVBORw0KGgoAAAANSUhEUgAAAFAAAAAwCAAAAACjjqIrAAAAR0lEQVR4nO3UIQ4AMAhD0R6i978lfp5sM3TJxK+GlwqCyhWMSw5H8YaAgN+B7er3O7chQEBAQEDAV+A4gICAgCewf6Np4g0XIF9B/zPJTK4AAAAASUVORK5CYII=",
                "markInfo":{"floorName":"1F","storages":[
                  {"identity":{"id":1,"no":"A1"},"pose":{"real":{"x":3.5,"y":3.6}}},
                  {"identity":{"id":2,"no":"P1"},"pose":{"real":{"x":6.8,"y":0.6}},"parkspot":{}}
                ]}
              }]
            }
            """.utf8),
        RobotFeed.navPath.rawValue: Data(#"{"path":{"poses":[{"x":3.5,"y":2.0},{"x":3.5,"y":3.6}]}}"#.utf8)
    ]

    public func connect(to endpoint: Endpoint) async throws {
        calls.append(.connect)
        disconnect()
        if failuresBeforeConnect > 0 {
            failuresBeforeConnect -= 1
            throw TransportError.disconnected
        }
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        connected = true
    }

    public func disconnect() {
        connected = false
        topics.removeAll()
        continuation.finish()
    }

    public func failConnections(_ count: Int) {
        failuresBeforeConnect = max(0, count)
    }

    public func enqueue(_ response: Response, for type: String) {
        queued[type, default: []].append(response)
    }

    public func setSubscription(_ topics: Set<String>, enabled: Bool) async throws {
        guard connected else { throw TransportError.disconnected }
        calls.append(.subscription(topics, enabled: enabled))
        if enabled { self.topics.formUnion(topics) }
        else { self.topics.subtract(topics) }
    }

    public func request(type: String, body: Data, timeout: Duration) async throws -> Reply {
        guard connected else { throw TransportError.disconnected }
        calls.append(.request(type: type, body: body))
        if var responses = queued[type], !responses.isEmpty {
            let next = responses.removeFirst()
            queued[type] = responses
            switch next {
            case .success(let body): return Reply(type: type, body: body, ok: true, message: "")
            case .delayed(let body, let duration):
                try await Task.sleep(for: duration)
                return Reply(type: type, body: body, ok: true, message: "")
            case .rejected(let message): return Reply(type: type, body: Data("{}".utf8), ok: false, message: message)
            case .timeout: throw TransportError.timeout
            }
        }
        return Reply(type: type, body: snapshots[type] ?? Data("{}".utf8), ok: true, message: "")
    }

    public func sendCommand(type: String, body: Data) async throws {
        guard connected else { throw TransportError.disconnected }
        calls.append(.command(type: type, body: body))
    }

    public func publish(_ feed: RobotFeed, body: Data) {
        guard connected, topics.contains(feed.rawValue) else { return }
        continuation.yield(.notification(type: feed.rawValue, body: body))
    }

    public func replayTask(paused: Bool) {
        let state = paused ? 4 : 3
        publish(.robotState, body: Data(#"{"state":4}"#.utf8))
        publish(.taskProc, body: Data("{\"type\":1,\"state\":\(state),\"dest\":\"A1\"}".utf8))
    }

    public func dropConnection() {
        guard connected else { return }
        continuation.yield(.stateChanged(.disconnected))
        disconnect()
    }
}
