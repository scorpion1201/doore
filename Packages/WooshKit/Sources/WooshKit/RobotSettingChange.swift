import Foundation
import SwiftProtobuf

/// The per-setting request mapping is kept here because the original apps' mapping
/// was inferred. The message types and fields are from the restored definitions.
public enum RobotSettingChange: Sendable {
    public enum Flag: CaseIterable, Sendable {
        case autoCharge, autoPark, goodsCheck, cableMotion, occupancy, muteCall, programMute, hold
    }

    case controlMode(Int)
    case identity(String)
    case server(String, UInt32)
    case flag(Flag, Bool)
    case thresholds(low: UInt32, idle: UInt32, full: UInt32, alarm: UInt32)
    case sound(volume: UInt32, mute: Bool)
    case speech(String)
    case step(mode: Int, value: Float, speed: Float, angle: Float, avoid: Bool)
    case cancelStep

    private var message: any SwiftProtobuf.Message {
        switch self {
        case .controlMode(let index):
            return Woosh_Robot_SwitchControlMode.with { $0.mode = .init(rawValue: index) ?? .kControlModeUndefined }
        case .identity(let name):
            return Woosh_Robot_Setting_Identity.with { $0.name = name }
        case .server(let host, let port):
            return Woosh_Robot_Setting_Server.with { $0.ip = host; $0.port = port }
        case .flag(let flag, let enabled):
            switch flag {
            case .autoCharge: return Woosh_Robot_Setting_AutoCharge.with { $0.allow = enabled }
            case .autoPark: return Woosh_Robot_Setting_AutoPark.with { $0.allow = enabled }
            case .goodsCheck: return Woosh_Robot_Setting_GoodsCheck.with { $0.allow = enabled }
            case .cableMotion: return Woosh_Robot_SetCableMotion.with { $0.allow = enabled }
            case .occupancy: return Woosh_Robot_SetOccupancy.with { $0.occupy = enabled }
            case .muteCall: return Woosh_Robot_SetMuteCall.with { $0.mute = enabled }
            case .programMute: return Woosh_Robot_SetProgramMute.with { $0.mute = enabled }
            case .hold: return Woosh_Robot_SetHoldMode.with { $0.hold = enabled }
            }
        case .thresholds(let low, let idle, let full, let alarm):
            return Woosh_Robot_Setting_Power.with { $0.low = low; $0.idle = idle; $0.full = full; $0.alarm = alarm }
        case .sound(let volume, let mute):
            return Woosh_Robot_Setting_Sound.with { $0.volume = volume; $0.mute = mute }
        case .step(let mode, let value, let speed, let angle, let avoid):
            return Woosh_Ros_CallAction.with {
                $0.stepControl.action = .kExecute
                $0.stepControl.avoid = avoid ? 1 : 0
                $0.stepControl.steps = [.with {
                    $0.mode = .init(rawValue: mode) ?? .kNone
                    $0.value = value
                    $0.speed = speed
                    if mode == 4 { $0.angle = angle }
                }]
            }
        case .cancelStep:
            return Woosh_Ros_CallAction.with { $0.stepControl = .with { $0.action = .kCancel } }
        case .speech(let text):
            return Woosh_Robot_Speak.with { $0.text = text }
        }
    }

    public var type: String { Swift.type(of: message).protoMessageName }

    public var body: Data {
        get throws {
            var options = JSONEncodingOptions()
            options.alwaysPrintEnumsAsInts = true
            // These messages contain only finite scalars and UTF-8 strings.
            return try message.jsonUTF8Data(options: options)
        }
    }

    public func allows(_ snapshot: RobotSnapshot) -> Bool {
        switch self {
        case .controlMode(let number): return [1, 2, 3].contains(number) && snapshot.controlMode != nil
        case .identity(let value): return snapshot.name != nil && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .server(let address, let port):
            return snapshot.serverHost != nil && Self.isIPv4(address) && (1...65_535).contains(port)
        case .flag(let flag, _): return snapshot.reported(flag) != nil
        case .thresholds(let low, let idle, let full, let alarm):
            return snapshot.thresholds["alarm"] != nil && [low, idle, full, alarm].allSatisfy { $0 <= 100 } && low <= idle && idle <= full
        case .sound(let volume, _): return volume <= 100 && snapshot.volume != nil && snapshot.soundMute != nil
        case .step(let mode, let value, let speed, let angle, _):
            return snapshot.allowsMotion && snapshot.state == 2 && (1...4).contains(mode) &&
                value.isFinite && value != 0 && speed.isFinite && speed > 0 && angle.isFinite
        case .cancelStep: return true
        case .speech(let value): return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains(String($0)) } && UInt8($0) != nil
        }
    }
}

extension RobotSnapshot {
    public func reported(_ flag: RobotSettingChange.Flag) -> Bool? {
        switch flag {
        case .autoCharge: return settingsFlags["autoCharge"]
        case .autoPark: return settingsFlags["autoPark"]
        case .goodsCheck: return settingsFlags["goodsCheck"]
        case .cableMotion: return software.map { $0 & 128 != 0 }
        case .occupancy: return software.map { $0 & 8 != 0 }
        case .muteCall: return software.map { $0 & 16 != 0 }
        case .programMute: return software.map { $0 & 32 != 0 }
        case .hold: return software.map { $0 & 64 != 0 }
        }
    }
}
