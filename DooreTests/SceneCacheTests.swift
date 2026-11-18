import Foundation
import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class SceneCacheTests: XCTestCase {
    private func scene(_ name: String, mapName: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["name": name, "maps": [["id": 1, "name": mapName]]])
    }

    func testCacheUsesIdentityAndAtomicallyReplacesPerScene() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SceneCache(root: root)
        let name = "../../maps/현장"
        cache.store(try scene(name, mapName: "old"), robot: "17", scene: name)
        cache.store(try scene(name, mapName: "updated"), robot: "17", scene: name)
        cache.store(try scene(name, mapName: "other"), robot: "18", scene: name)
        cache.store(try scene(name, mapName: "no"), robot: "../17", scene: name)
        let latest = await cache.load(robot: "17", scene: name)
        let other = await cache.load(robot: "18", scene: name)
        let missing = await cache.load(robot: "17", scene: "현장")
        XCTAssertEqual(latest?.maps.first?.name, "updated")
        XCTAssertEqual(other?.maps.first?.name, "other")
        XCTAssertNil(missing)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(Set(names), ["17", "18"])
        let files = try XCTUnwrap(FileManager.default.subpaths(atPath: root.path))
        XCTAssertEqual(files.filter { $0.hasSuffix("/scene.json") }.count, 2)
        XCTAssertFalse(files.contains { $0.contains("maps") })
    }

    func testSyncPreviewIsReadOnlyAndYieldsToLiveData() async throws {
        let token = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(token)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: token))
        defer {
            defaults.removePersistentDomain(forName: token)
            try? FileManager.default.removeItem(at: root)
        }
        let cache = SceneCache(root: root)
        cache.store(try scene("West", mapName: "cached"), robot: "17", scene: "West")
        let fake = FakeRobotTransport()
        let robot = RobotStore(settings: SettingsStore(defaults: defaults),
                               session: RobotSession(transport: fake), sceneCache: cache)
        let report = #"{"robotId":17,"state":2,"scene":{"sceneName":"West","mapId":1}}"#
        await fake.enqueue(.success(Data(report.utf8)), for: RobotFeed.robotInfo.rawValue)
        await fake.enqueue(.delayed(try scene("West", mapName: "live"), by: .milliseconds(450)), for: RobotFeed.sceneData.rawValue)
        let connect = Task { await robot.connect(host: "192.0.2.17", port: 5480) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while robot.syncingMapPreview == nil && clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(robot.syncingMapPreview?.name, "cached")
        XCTAssertNil(robot.activeMap)
        XCTAssertNil(robot.sceneData)
        await connect.value
        while robot.state != .ready && clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNil(robot.syncingMapPreview)
        XCTAssertEqual(robot.activeMap?.name, "live")
        let persisted = await cache.load(robot: "17", scene: "West")
        XCTAssertEqual(persisted?.maps.first?.name, "live")
        await robot.disconnect()
    }
}
