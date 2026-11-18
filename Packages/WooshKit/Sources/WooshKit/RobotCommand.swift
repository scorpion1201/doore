import Foundation
import SwiftProtobuf

public enum TaskControl: Int, Sendable, Identifiable {
    case pause = 2, resume, cancel
    public var id: Int { rawValue }
}

public enum MapBuildOperation: Int, Sendable {
    case add = 1, update, cancel, save
}

/// Commands use the restored descriptors for both the message name and JSON representation.
public enum RobotCommand: Sendable {
    case taskControl(TaskControl)
    case taskSubmission(TaskSubmission)
    case initializeInPlace
    case initializeQR
    case setPose(mapID: String, pose: MapPose)
    case wifi(WiFiOperation)
    case workMode(Int)
    case buildMap(MapBuildOperation, scene: String, name: String)
    case startPredefined(Int)
    case changeSetting(RobotSettingChange)
    case sceneOperation(SceneOperation)
    case station(StationChange)

    public var type: String {
        switch self {
        case .taskSubmission(let submission): return submission.type
        case .taskControl: return Woosh_Robot_ActionOrder.protoMessageName
        case .initializeInPlace, .initializeQR: return Woosh_Robot_InitRobot.protoMessageName
        case .setPose: return Woosh_Robot_SetRobotPose.protoMessageName
        case .wifi(let operation): return operation.type
        case .workMode: return Woosh_Robot_SwitchWorkMode.protoMessageName
        case .buildMap: return Woosh_Robot_BuildMap.protoMessageName
        case .startPredefined: return Woosh_Robot_ExecPreTask.protoMessageName
        case .changeSetting(let change): return change.type
        case .station(let change): return change.type
        case .sceneOperation(let operation): return operation.type
        }
    }

    public var body: Data {
        get throws {
            let message: any SwiftProtobuf.Message
            switch self {
            case .taskSubmission(let submission): return try submission.body
            case .taskControl(let action):
                message = Woosh_Robot_ActionOrder.with { $0.order = Woosh_Action_Order(rawValue: action.rawValue)! }
            case .initializeInPlace:
                message = Woosh_Robot_InitRobot.with { $0.isRecord = true }
            case .initializeQR:
                message = Woosh_Robot_InitRobot.with { $0.isQrcode = true }
            case .setPose(_, let pose):
                message = Woosh_Robot_SetRobotPose.with {
                    $0.pose = .with { $0.x = Float(pose.x); $0.y = Float(pose.y); $0.theta = Float(pose.theta) }
                }
            case .wifi(let operation): return try operation.body
            case .workMode(let mode):
                guard (1...3).contains(mode) else { throw SessionError.modeMismatch }
                message = Woosh_Robot_SwitchWorkMode.with { $0.mode = Woosh_Robot_WorkMode(rawValue: mode)! }
            case .buildMap(let operation, let scene, let name):
                message = Woosh_Robot_BuildMap.with {
                    $0.type = Woosh_Robot_BuildMap.BuildType(rawValue: operation.rawValue)!
                    if operation == .add || operation == .update { $0.sceneName = scene; $0.mapName = name }
                }
            case .startPredefined(let id):
                guard let number = Int32(exactly: id) else { throw SessionError.modeMismatch }
                message = Woosh_Robot_ExecPreTask.with { $0.taskSetID = number }
            case .changeSetting(let change): return try change.body
            case .station(let change): return try change.body
            case .sceneOperation(let operation): return try operation.body
            }
            var options = JSONEncodingOptions()
            options.alwaysPrintEnumsAsInts = true
            return try message.jsonUTF8Data(options: options)
        }
    }
}

public struct RobotVelocity: Sendable, Equatable {
    public let linear: Double
    public let angular: Double
    public let lateral: Double
    public init(linear: Double, angular: Double, lateral: Double = 0) {
        self.linear = linear
        self.angular = angular
        self.lateral = lateral
    }
    public static let zero = Self(linear: 0, angular: 0)

    var body: Data? {
        guard linear.isFinite, angular.isFinite, lateral.isFinite else { return nil }
        var components = ["linear": linear, "angular": angular]
        if lateral != 0 { components["linearY"] = lateral }
        return try? JSONEncoder().encode(components)
    }
}

/// Keeps just the current deflection. A slow write skips ticks instead of accumulating them.
actor VelocityLoop {
    private let transport: any RobotTransport
    private var latest = RobotVelocity.zero
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var braking: Task<Void, Never>?
    private static let twist = Woosh_Robot_Twist.protoMessageName

    init(transport: any RobotTransport) { self.transport = transport }

    func update(_ velocity: RobotVelocity) async {
        guard velocity != .zero, velocity.body != nil else { await stop(); return }
        guard braking == nil else { return }
        latest = velocity
        guard worker == nil else { return }
        let token = generation
        worker = Task { [weak self] in await self?.run(token) }
    }

    private func run(_ token: UUID) async {
        let clock = ContinuousClock()
        let interval = Duration.nanoseconds(1_000_000_000 / 15)
        while token == generation && !Task.isCancelled, let body = latest.body {
            let next = clock.now.advanced(by: interval)
            do {
                try await transport.sendCommand(type: Self.twist, body: body)
            } catch {
                if token == generation { await stop() }
                return
            }
            guard token == generation else { return }
            do { try await clock.sleep(until: next) } catch { return }
        }
    }

    func stop() async {
        if let braking { await braking.value; return }
        guard worker != nil, let zero = RobotVelocity.zero.body else { return }
        generation = UUID()
        worker?.cancel()
        worker = nil
        latest = .zero
        let writes = Task { [transport] in
            for _ in 0..<2 { try? await transport.sendCommand(type: Self.twist, body: zero) }
        }
        braking = writes
        await writes.value
        braking = nil
    }
}
