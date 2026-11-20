import Foundation
import XCTest
@testable import WooshKit

final class StationShortcutTests: XCTestCase {
    func testExactExecTaskPayloads() throws {
        func payload(_ shortcut: StationShortcut) throws -> NSDictionary {
            let command = RobotCommand.stationShortcut(shortcut, scene: "Example", mapID: "1")
            XCTAssertEqual(command.type, Woosh_Robot_ExecTask.protoMessageName)
            let json = try JSONSerialization.jsonObject(with: command.body)
            return try XCTUnwrap(json as? NSDictionary)
        }
        XCTAssertEqual(try payload(.charge(station: nil)), ["type": 3])
        XCTAssertEqual(try payload(.charge(station: "C1")), ["type": 3, "markNo": "C1"])
        XCTAssertEqual(try payload(.park(station: "P1")), ["type": 2, "markNo": "P1"])
        XCTAssertThrowsError(try payload(.park(station: "")))
        XCTAssertThrowsError(try payload(.charge(station: " ")))
    }

    func testShortcutUsesCompatibleUnambiguousStationForThisRobot() throws {
        let scene = try SceneModel(data: Data("""
        {"name":"Example","maps":[{"id":1,"markInfo":{"storages":[
          {"identity":{"no":"A1"},"rack":{}},
          {"identity":{"no":"C1"},"charger":{"robots":[7]}},
          {"identity":{"no":"CP"},"charger":{"parking":true,"robots":[7]}},
          {"identity":{"no":"P1"},"parkspot":{}}
        ]}}]}
        """.utf8))
        let map = try XCTUnwrap(scene.maps.first)
        XCTAssertEqual(map.shortcut(for: .kCharge, selected: "C1", robotNumber: "7"), .charge(station: "C1"))
        XCTAssertNil(map.shortcut(for: .kCharge, selected: "C1", robotNumber: "8"))
        XCTAssertNil(map.shortcut(for: .kCharge, selected: "C1", robotNumber: nil))
        XCTAssertEqual(map.shortcut(for: .kCharge, selected: nil, robotNumber: "7"), .charge(station: nil))
        XCTAssertEqual(map.shortcut(for: .kCharge, selected: "A1", robotNumber: "7"), .charge(station: nil))
        XCTAssertEqual(map.shortcut(for: .kParking, selected: "CP", robotNumber: "7"), .park(station: "CP"))
        XCTAssertNil(map.shortcut(for: .kParking, selected: nil, robotNumber: "7"))
        XCTAssertEqual(map.shortcut(for: .kParking, selected: nil, robotNumber: "8"), .park(station: "P1"))
        XCTAssertEqual(map.shortcut(for: .kParking, selected: "C1", robotNumber: nil), .park(station: "P1"))
        XCTAssertNil(map.shortcut(for: .kPick, selected: "A1", robotNumber: "7"))
    }

    func testDuplicateTargetCannotBeSentByNumber() throws {
        let scene = try SceneModel(data: Data("""
        {"name":"Example","maps":[{"id":1,"markInfo":{"storages":[
          {"identity":{"no":"P1"},"parkspot":{}},{"identity":{"no":"P1"},"rack":{}}
        ]}}]}
        """.utf8))
        let map = try XCTUnwrap(scene.maps.first)
        XCTAssertNil(map.shortcut(for: .kParking, selected: "P1", robotNumber: nil))
        XCTAssertNil(map.shortcut(for: .kParking, selected: nil, robotNumber: nil))
    }

    func testExecutionRequiresCurrentScopeAndReportedIdleMode() {
        let parking = RobotCommand.stationShortcut(.park(station: "P1"), scene: "Example", mapID: "1")
        let automatic = RobotCommand.stationShortcut(.charge(station: nil), scene: nil, mapID: nil)
        var snapshot = RobotSnapshot()
        XCTAssertFalse(snapshot.allows(automatic))
        let idle = Data(#"{"state":2,"mode":{"ctrl":1,"work":2},"deviceState":{},"battery":{"chargeState":1}}"#.utf8)
        XCTAssertTrue(snapshot.apply(.robotInfo, data: idle))
        XCTAssertTrue(snapshot.allows(automatic))
        XCTAssertFalse(snapshot.allows(.stationShortcut(.park(station: "P1"), scene: nil, mapID: nil)))
        XCTAssertFalse(snapshot.allows(parking))
        XCTAssertTrue(snapshot.apply(.scene, data: Data(#"{"sceneName":"Example","mapId":1}"#.utf8)))
        XCTAssertTrue(snapshot.allows(parking))
        XCTAssertFalse(snapshot.allows(automatic))
        XCTAssertFalse(snapshot.allows(.stationShortcut(.charge(station: nil), scene: "Other", mapID: "1")))
        XCTAssertFalse(snapshot.allows(.stationShortcut(.park(station: "P1"), scene: "Example", mapID: "2")))
        for (feed, json): (RobotFeed, String) in [
            (.mode, #"{"ctrl":2,"work":2}"#), (.mode, #"{"ctrl":1,"work":1}"#),
            (.robotState, #"{"state":4}"#), (.battery, #"{"chargeState":2}"#),
            (.battery, "{}"), (.deviceState, #"{"hardware":1024}"#)
        ] {
            var changed = snapshot
            XCTAssertTrue(changed.apply(feed, data: Data(json.utf8)))
            XCTAssertFalse(changed.allows(parking))
        }
    }
}
