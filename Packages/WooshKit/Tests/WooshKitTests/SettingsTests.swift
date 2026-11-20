import Foundation
import XCTest
@testable import WooshKit

final class SettingsTests: XCTestCase {
    func testSoundAndBatteryWritesKeepAllReportedCompanionFields() throws {
        var report = RobotSnapshot()
        let snapshot = Data(#"{"power":{"alarm":7,"low":12,"idle":85,"full":96},"sound":{"volume":30,"mute":true}}"#.utf8)
        XCTAssertTrue(report.apply(.setting, data: snapshot))
        let sound = RobotSettingChange.sound(volume: 42, mute: try XCTUnwrap(report.soundMute))
        XCTAssertTrue(sound.allows(report))
        XCTAssertEqual(sound.type, "woosh.robot.setting.Sound")
        XCTAssertTrue(try Woosh_Robot_Setting_Sound(jsonUTF8Data: sound.body).mute)
        XCTAssertFalse(RobotSettingChange.thresholds(low: 91, idle: 20, full: 95, alarm: 7).allows(report))
    }

    func testMissingSettingsCannotBeOverwritten() {
        let report = RobotSnapshot()
        XCTAssertFalse(RobotSettingChange.sound(volume: 30, mute: false).allows(report))
        XCTAssertFalse(RobotSettingChange.flag(.autoCharge, true).allows(report))
        XCTAssertFalse(RobotSettingChange.controlMode(1).allows(report))
        XCTAssertFalse(RobotSettingChange.speech(" ").allows(report))
    }

    func testAddingStationRequiresCurrentMapAndDeploymentMode() throws {
        let command = StationChange.add(mapID: "3", number: "A1", pose: MapPose(x: 2, y: 3), kind: .charger)
        var report = RobotSnapshot()
        XCTAssertFalse(command.allows(report))
        XCTAssertTrue(report.apply(.mode, data: Data(#"{"ctrl":1,"work":1}"#.utf8)))
        XCTAssertTrue(report.apply(.scene, data: Data(#"{"mapId":3}"#.utf8)))
        XCTAssertTrue(report.apply(.poseSpeed, data: Data(#"{"mapId":3}"#.utf8)))
        XCTAssertTrue(command.allows(report))
        let create = try Woosh_Map_Mark_Storage_Create(jsonUTF8Data: command.body)
        XCTAssertEqual(create.storage.identity.no, "A1")
        XCTAssertEqual(create.storage.pose.real.y, 3)
        XCTAssertEqual(create.storage.category, .charger(.init()))
        XCTAssertTrue(report.apply(.mode, data: Data(#"{"ctrl":1,"work":2}"#.utf8)))
        XCTAssertFalse(command.allows(report))
    }
}
