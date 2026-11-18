import Foundation
import SwiftProtobuf

/// A projection of the public JSON fields documented in the behavior report.
/// An absent or unrecognized value remains unknown, including during initial sync.
public struct RobotSnapshot: Sendable {
    public private(set) var name: String?
    public private(set) var number: String?
    public private(set) var state: Int?
    public private(set) var controlMode: Int?
    public private(set) var workMode: Int?
    public private(set) var battery: Int?
    public private(set) var chargeState: Int?
    public private(set) var taskState: Int?
    public private(set) var taskType: Int?
    public private(set) var action: Int?
    public private(set) var destination: String?
    public private(set) var mapID: String?
    public private(set) var poseMapID: String?
    public private(set) var pose: MapPose?
    public private(set) var sceneName: String?
    public private(set) var wifiStrength: Int?
    public private(set) var hardware: Int?
    public private(set) var software: Int?
    public private(set) var statusCode: String?
    public private(set) var statusMessage: String?
    public private(set) var volume: Int?
    public private(set) var settingsFlags: [String: Bool] = [:]
    public private(set) var thresholds: [String: Int] = [:]
    public private(set) var serverHost: String?
    public private(set) var serverPort: Int?
    public private(set) var wifiName: String?
    public private(set) var wifiMode: Int?
    public private(set) var wifiList: Data?

    public private(set) var modelName: String?
    public private(set) var systemVersion: String?
    public private(set) var length: Int?
    public private(set) var width: Int?
    public private(set) var height: Int?
    public private(set) var linear: Double?
    public private(set) var angular: Double?
    public private(set) var soundMute: Bool?

    public init() {}

    public var emergencyStopped: Bool? { hardware.map { $0 & 1024 != 0 } }
    public var charging: Bool? {
        if state == 8 || chargeState == 2 || chargeState == 3 { return true }
        return chargeState == 1 ? false : nil
    }

    public var allowsMotion: Bool {
        guard emergencyStopped == false, charging == false, let state,
              [2, 4, 9].contains(state) else { return false }
        if state == 4 { return taskState == 4 }
        if let taskState { return [1, 2, 4, 7, 8, 9].contains(taskState) }
        return true
    }

    public func allows(_ command: RobotCommand) -> Bool {
        switch command {
        case .changeSetting(let change): return change.allows(self)
        case .station(let change): return change.allows(self)
        case .sceneOperation(let operation): return operation.allows(self)
        case .startPredefined(let id):
            return Int32(exactly: id) != nil && controlMode == 1 && workMode == 2 && state == 2
        case .workMode(let mode): return (1...3).contains(mode) && controlMode == 1 && state != nil
        case .initializeInPlace, .initializeQR: return state == 1 || state == 2
        case .wifi(let operation): return operation.allows(self)
        case .setPose(let id, let pose):
            return (state == 1 || state == 2) && mapID == id && [pose.x, pose.y, pose.theta].allSatisfy { Float($0).isFinite }
        case .taskSubmission(let submission): return submission.allows(self)
        case .taskControl(let control):
            guard state == 4, workMode == 2, controlMode == 1 else { return false }
            switch control {
            case .pause: return taskState == 3
            case .resume: return taskState == 4 && emergencyStopped == false
            case .cancel: return [3, 4, 5, 6].contains(taskState ?? -1)
            }
        case .buildMap(let operation, let scene, let name):
            guard controlMode == 1, workMode == 1 else { return false }
            switch operation {
            case .add, .update: return state == 2 && !scene.isEmpty && !name.isEmpty
            case .cancel, .save: return state == 9
            }
        }
    }

    @discardableResult
    public mutating func apply(_ feed: RobotFeed, data: Data) -> Bool {
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        func decode<M: SwiftProtobuf.Message>(_ type: M.Type) throws -> M {
            try M(jsonUTF8Data: data, options: options)
        }
        do {
            switch feed {
            case .robotInfo:
                let report = try decode(Woosh_Robot_RobotInfo.self)
                self = Self()
                if report.commu != nil { number = String(report.robotID) }
                state = report.state.rawValue
                if report.hasGenral {
                    modelName = report.genral.displayModel
                    if report.genral.hasVersion { systemVersion = report.genral.version.system }
                    if report.genral.hasModelData {
                        length = Int(report.genral.modelData.length)
                        width = Int(report.genral.modelData.width)
                        height = Int(report.genral.modelData.height)
                    }
                }
                if report.hasSetting { apply(report.setting) }
                if report.hasMode { apply(report.mode) }
                if report.hasDeviceState { apply(report.deviceState) }
                if report.hasPoseSpeed { apply(report.poseSpeed) }
                if report.hasBattery { apply(report.battery) }
                if report.hasNetwork { apply(report.network) }
                if report.hasTaskProc { apply(report.taskProc) }
                if report.hasScene { apply(report.scene) }
                apply(report.abnormalCodes.scs.last ?? report.statusCodes.scs.last)
            case .robotState: state = try decode(Woosh_Robot_RobotState.self).state.rawValue
            case .setting: apply(try decode(Woosh_Robot_Setting.self))
            case .mode: apply(try decode(Woosh_Robot_Mode.self))
            case .poseSpeed: apply(try decode(Woosh_Robot_PoseSpeed.self))
            case .battery: apply(try decode(Woosh_Robot_Battery.self))
            case .network: apply(try decode(Woosh_Robot_Network.self))
            case .scene: apply(try decode(Woosh_Robot_Scene.self))
            case .taskProc: apply(try decode(Woosh_Robot_TaskProc.self))
            case .deviceState: apply(try decode(Woosh_Robot_DeviceState.self))
            case .statusCode: apply(try decode(Woosh_Robot_Count_StatusCode.self))
            case .abnormalCodes: apply(try decode(Woosh_Robot_Count_AbnormalCodes.self).scs.last)
            default: break
            }
            return true
        } catch {
            return false
        }
    }

    private mutating func apply(_ settings: Woosh_Robot_Setting) {
        name = settings.hasIdentity ? settings.identity.name : nil
        volume = settings.hasSound ? Int(settings.sound.volume) : nil
        soundMute = settings.hasSound ? settings.sound.mute : nil
        settingsFlags = settings.hasAllow ? [
            "autoCharge": settings.allow.autoCharge, "autoPark": settings.allow.autoPark,
            "goodsCheck": settings.allow.goodsCheck, "autoHold": settings.allow.autoHold,
            "mechanismCheck": settings.allow.mechanismCheck
        ] : [:]
        thresholds = settings.hasPower ? [
            "full": Int(settings.power.full), "low": Int(settings.power.low),
            "idle": Int(settings.power.idle), "alarm": Int(settings.power.alarm)
        ] : [:]
        serverHost = settings.hasServer ? settings.server.ip : nil
        serverPort = settings.hasServer ? Int(settings.server.port) : nil
    }

    private mutating func apply(_ mode: Woosh_Robot_Mode) {
        controlMode = mode.ctrl.rawValue
        workMode = mode.work.rawValue
    }

    private mutating func apply(_ value: Woosh_Robot_PoseSpeed) {
        poseMapID = String(value.mapID)
        pose = value.hasPose ? MapPose(value.pose) : nil
        linear = value.hasTwist ? Double(value.twist.linear) : nil
        angular = value.hasTwist ? Double(value.twist.angular) : nil
    }

    private mutating func apply(_ value: Woosh_Robot_Battery) {
        battery = value.power <= 100 ? Int(value.power) : nil
        chargeState = value.chargeState.rawValue
    }

    private mutating func apply(_ network: Woosh_Robot_Network) {
        wifiStrength = network.hasWifi ? Int(network.wifi.strength) : nil
        wifiName = network.hasWifi ? network.wifi.name : nil
        wifiMode = network.hasWifi ? network.wifi.mode.rawValue : nil
        wifiList = network.hasWifi ? network.wifi.listJson : nil
    }

    private mutating func apply(_ scene: Woosh_Robot_Scene) {
        mapID = String(scene.mapID)
        sceneName = scene.sceneName
    }

    private mutating func apply(_ task: Woosh_Robot_TaskProc) {
        taskState = task.state.rawValue
        taskType = task.type.rawValue
        action = task.hasAction ? task.action.type.rawValue : nil
        destination = task.dest
    }

    private mutating func apply(_ device: Woosh_Robot_DeviceState) {
        hardware = Int(device.hardware)
        software = Int(device.software)
    }

    private mutating func apply(_ code: Woosh_Robot_Count_StatusCode?) {
        statusCode = code.map { String($0.code) }
        statusMessage = code?.msg
    }
}
