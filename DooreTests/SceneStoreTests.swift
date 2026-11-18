import Foundation
import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class SceneStoreTests: XCTestCase {
    func testFailedPreviewAndRejectedEditPreserveSelectedScene() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeRobotTransport()
        let robot = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await robot.start()
        await robot.connect(host: "192.0.2.10", port: 5480)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while robot.state != .ready && clock.now < deadline { await Task.yield() }
        XCTAssertEqual(robot.state, .ready)

        let store = SceneStore()
        await fake.enqueue(.success(Data(#"{"scenes":[{"name":"West","maps":["F1"]},{"name":"East","maps":[]}]}"#.utf8)),
                           for: "woosh.map.SceneList")
        await fake.enqueue(.success(Data(#"{"name":"West","maps":[{"id":1,"name":"F1"}]}"#.utf8)), for: "woosh.map.SceneData")
        await store.reload(robot, preferred: "West")
        XCTAssertEqual(store.scene?.name, "West")

        await fake.enqueue(.rejected("busy"), for: "woosh.map.SceneData")
        await store.select("East", robot: robot)
        XCTAssertEqual(store.scene?.name, "West")
        XCTAssertEqual(robot.errorMessage, "busy")
        await fake.enqueue(.rejected("in use"), for: "woosh.map.Delete")
        await store.apply(.deleteMap(scene: "West", map: "F1"), robot: robot, preferred: "West")
        XCTAssertEqual(store.scene?.maps.map(\.name), ["F1"])
        XCTAssertEqual(robot.errorMessage, "in use")

        let before = await fake.calls.count
        await store.apply(.renameScene(scene: "West", to: "East"), robot: robot, preferred: nil)
        let after = await fake.calls.count
        XCTAssertEqual(after, before)
        await robot.disconnect()
    }
}
