import Foundation
import XCTest
@testable import WooshKit
import WooshKitTesting

final class SceneOperationTests: XCTestCase {
    func testNamesAndExplicitOperationScope() throws {
        let accepted = SceneOperation.renameScene(scene: "West", to: "동관~2_#=")
        XCTAssertTrue(accepted.allows(RobotSnapshot()))
        XCTAssertFalse(SceneOperation.renameScene(scene: "West", to: "West").allows(RobotSnapshot()))
        for name in ["", "A B", "A/B", "A:B", "A\n"] {
            XCTAssertFalse(SceneOperation.validNewName(name))
        }
        XCTAssertFalse(SceneOperation.deleteMap(scene: "West", map: "").allows(RobotSnapshot()))
        let commands: [(SceneOperation, String, NSDictionary)] = [
            (.renameScene(scene: "West", to: "East"), "woosh.map.Rename", ["oldSceneName": "West", "newSceneName": "East"]),
            (.renameMap(scene: "West", map: "F1", to: "B2"), "woosh.map.Rename",
             ["oldSceneName": "West", "oldMapName": "F1", "newMapName": "B2"]),
            (.deleteMap(scene: "West", map: "F1"), "woosh.map.Delete", ["sceneName": "West", "mapName": "F1"]),
            (.deleteScene(scene: "West"), "woosh.map.Delete", ["sceneName": "West"]),
            (.useMap(scene: "West", map: "F1", reset: true), "woosh.robot.SwitchMap",
             ["sceneName": "West", "mapName": "F1", "userReset": true])
        ]
        for (operation, type, fields) in commands {
            XCTAssertEqual(operation.type, type)
            let body = try JSONSerialization.jsonObject(with: operation.body)
            XCTAssertEqual(body as? NSDictionary, fields)
        }
    }

    func testDirectoryThenNamedPreviewAndRejection() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: Endpoint(host: "192.0.2.10"))
        let list = #"{"scenes":[{"name":"West","maps":["F1","B2"],"newField":1},{"name":"East"},{"name":"West"}]}"#
        await fake.enqueue(.success(Data(list.utf8)), for: "woosh.map.SceneList")
        let entries = try await session.sceneDirectory()
        XCTAssertEqual(entries.map(\.name), ["West", "East"])
        XCTAssertEqual(entries.first?.maps, ["F1", "B2"])
        await fake.enqueue(.success(Data(#"{"name":"West","maps":[{"id":1,"name":"F1"}]}"#.utf8)),
                           for: "woosh.map.SceneData")
        let preview = try await session.scenePreview(named: "West")
        XCTAssertEqual(preview.maps.first?.name, "F1")
        guard case .request(let type, let body) = await fake.calls.last else { return XCTFail("Missing scene read") }
        XCTAssertEqual(type, "woosh.map.SceneData")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["name": "West"])
        await fake.enqueue(.rejected("scene in use"), for: "woosh.map.Delete")
        do {
            try await session.perform(.sceneOperation(.deleteScene(scene: "West")))
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? SessionError, .rejected("scene in use"))
        }
        await fake.enqueue(.success(Data(#"{"name":"East","maps":[]}"#.utf8)), for: "woosh.map.SceneData")
        do {
            _ = try await session.scenePreview(named: "West")
            XCTFail("A preview must belong to the requested scene")
        } catch {
            XCTAssertEqual(error as? TransportError, .invalidEnvelope)
        }
        await session.disconnect()
    }
}
