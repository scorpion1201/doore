import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class RobotStoreTests: XCTestCase {
    func testHistoryPersistsOnlyOnSuccessfulSyncAndDisconnectClearsLiveData() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.language, "ko")
        let fake = FakeRobotTransport()
        let store = RobotStore(settings: settings, session: RobotSession(transport: fake))
        await store.start()
        await fake.enqueue(.rejected("busy"), for: RobotFeed.robotInfo.rawValue)
        await store.connect(host: "192.0.2.9", port: 5480)
        XCTAssertEqual(store.errorMessage, "busy")
        XCTAssertFalse(store.errorMessageIsLocal)
        XCTAssertTrue(settings.history.isEmpty)
        await store.retry()
        try await wait { store.state == .ready && !settings.history.isEmpty }
        XCTAssertEqual(store.battery, 82)
        let settingsAgain = SettingsStore(defaults: defaults)
        XCTAssertEqual(settingsAgain.history.first?.host, "192.0.2.9")
        await store.disconnect()
        try await wait { store.state == .disconnected }
        XCTAssertNil(store.battery)
        XCTAssertNil(store.scene)
    }

    func testInvalidAddressAndUnreportedModeProduceNoCommand() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeRobotTransport(snapshots: [:])
        let store = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await store.connect(host: "bad/address", port: 5480)
        let initial = await fake.calls
        XCTAssertTrue(initial.isEmpty)
        await store.connect(host: "192.0.2.2", port: 5480)
        try await wait { store.state == .ready }
        let before = await fake.calls
        XCTAssertNil(store.prepareControl(.resume))
        await store.buildMap(.add, name: "example")
        let after = await fake.calls
        XCTAssertEqual(before, after)
    }

    func testTaskControlsConfirmTheSameRobotTaskAndWait() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeRobotTransport()
        let store = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        func publishWait(task: Int64, waitID: Int32) async throws {
            let body = try Woosh_Robot_TaskProc.with {
                $0.robotTaskID = task
                $0.state = .kActionWait
                $0.action.waitID = waitID
            }.jsonUTF8Data()
            await fake.publish(.taskProc, body: body)
        }
        await store.connect(host: "192.0.2.12", port: 5480)
        try await wait { store.state == .ready }
        await fake.publish(.robotState, body: Data(#"{"state":4}"#.utf8))
        try await publishWait(task: 41, waitID: 1)
        try await wait { store.prepareControl(.breakWait) != nil }
        let firstWait = try XCTUnwrap(store.prepareControl(.breakWait))
        let firstCancel = try XCTUnwrap(store.prepareControl(.cancel))
        let before = await fake.calls

        try await publishWait(task: 41, waitID: 2)
        try await wait { store.prepareControl(.breakWait) != firstWait }
        await store.controlTask(firstWait)
        XCTAssertEqual(store.prepareControl(.cancel), firstCancel)
        try await publishWait(task: 42, waitID: 2)
        try await wait { store.prepareControl(.cancel) != firstCancel }
        await store.controlTask(firstCancel)
        let afterStale = await fake.calls
        XCTAssertEqual(afterStale, before)

        let current = try XCTUnwrap(store.prepareControl(.breakWait))
        await store.controlTask(current)
        let sent = await fake.calls
        XCTAssertEqual(Array(sent.dropFirst(before.count)), [
            .request(type: Woosh_Robot_ActionOrder.protoMessageName,
                     body: try RobotCommand.taskControl(.breakWait).body)
        ])
        XCTAssertEqual(store.taskStateLabel, "동작 대기")

        await store.setActive(false)
        await store.setActive(true)
        try await wait { store.state == .ready }
        await fake.publish(.robotState, body: Data(#"{"state":4}"#.utf8))
        try await publishWait(task: 42, waitID: 2)
        try await wait { store.prepareControl(.breakWait) != nil }
        let reconnected = await fake.calls
        await store.controlTask(current)
        let afterReconnection = await fake.calls
        XCTAssertEqual(afterReconnection, reconnected)
        await store.disconnect()
    }

    func testNavigationPathBelongsToTheReportedSceneAndMap() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeRobotTransport()
        let store = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await store.connect(host: "192.0.2.10", port: 5480)
        try await wait { store.state == .ready }
        XCTAssertFalse(store.navPath.isEmpty)

        await fake.publish(.scene, body: Data(#"{"sceneName":"예시","mapId":2}"#.utf8))
        try await wait { store.currentMapID == "2" }
        XCTAssertTrue(store.navPath.isEmpty)

        await fake.publish(.navPath, body: Data(#"{"path":{"poses":[{"x":7,"y":3}]}}"#.utf8))
        try await wait { store.navPath == [MapPose(x: 7, y: 3)] }
        await fake.publish(.scene, body: Data(#"{"sceneName":"예시","mapId":2}"#.utf8))
        await fake.publish(.battery, body: Data(#"{"power":64}"#.utf8))
        try await wait { store.battery == 64 }
        XCTAssertEqual(store.navPath, [MapPose(x: 7, y: 3)])

        await fake.publish(.scene, body: Data(#"{"sceneName":"예시-02","mapId":2}"#.utf8))
        try await wait { store.snapshot.sceneName == "예시-02" }
        XCTAssertTrue(store.navPath.isEmpty)
        await store.disconnect()
    }

    func testPresetConfirmationCannotStartAReplacementPresetOrAnotherRobot() async throws {
        func scene(withPreset name: String) throws -> Data {
            try Woosh_Map_SceneData.with {
                $0.name = "예시"
                $0.taskInfo.repeatTasks = [.with {
                    $0.taskSet.base.id = 7
                    $0.taskSet.base.name = name
                }]
            }.jsonUTF8Data()
        }
        var snapshots = FakeRobotTransport.exampleSnapshots
        snapshots[RobotFeed.sceneData.rawValue] = try scene(withPreset: "예시-01")
        let fake = FakeRobotTransport(snapshots: snapshots)
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await store.connect(host: "192.0.2.10", port: 5480)
        try await wait { store.state == .ready }
        let original = try XCTUnwrap(store.scene?.predefinedSets.first)
        let pending = try XCTUnwrap(store.prepareStart(of: original))

        await fake.enqueue(.success(try scene(withPreset: "예시-02")), for: RobotFeed.sceneData.rawValue)
        try await store.session.refreshScene()
        try await wait { store.scene?.predefinedSets.first?.name == "예시-02" }
        let beforeReplacement = await fake.calls
        await store.startPredefined(pending)
        let afterReplacement = await fake.calls
        XCTAssertEqual(afterReplacement, beforeReplacement)

        await store.disconnect()
        await store.connect(host: "192.0.2.11", port: 5480)
        try await wait { store.state == .ready && store.scene?.predefinedSets.first == original }
        let beforeReconnect = await fake.calls
        await store.startPredefined(pending)
        let afterReconnect = await fake.calls
        XCTAssertEqual(afterReconnect, beforeReconnect)

        let current = try XCTUnwrap(store.prepareStart(of: original))
        await store.startPredefined(current)
        let afterConfirmation = await fake.calls
        let start = RobotCommand.startPredefined(original.id)
        XCTAssertEqual(Array(afterConfirmation.dropFirst(beforeReconnect.count)), [.request(type: start.type, body: try start.body)])
        await store.disconnect()
    }

    func testStationShortcutRequiresFreshConfirmationAndWaitsForRobotState() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeRobotTransport()
        let store = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await store.connect(host: "192.0.2.10", port: 5480)
        try await wait { store.state == .ready }
        let park = try XCTUnwrap(store.prepareShortcut(.kParking, selected: nil))
        XCTAssertEqual(park.shortcut, .park(station: "P1"))
        let automatic = try XCTUnwrap(store.prepareShortcut(.kCharge, selected: nil))
        XCTAssertEqual(automatic.shortcut, .charge(station: nil))
        let type = Woosh_Robot_ExecTask.protoMessageName

        await fake.publish(.mode, body: Data(#"{"ctrl":2,"work":1}"#.utf8))
        try await wait { store.controlModeLabel == "수동" }
        await store.setting(.controlMode(Woosh_Robot_ControlMode.kAuto.rawValue))
        XCTAssertFalse(store.canSendShortcut(automatic))
        await fake.publish(.mode, body: Data(#"{"ctrl":1,"work":1}"#.utf8))
        try await wait { store.controlModeLabel == "자동" }
        await store.switchWorkMode(Woosh_Robot_WorkMode.kTaskMode.rawValue)
        XCTAssertFalse(store.canSendShortcut(automatic))
        await fake.publish(.mode, body: Data(#"{"ctrl":1,"work":2}"#.utf8))
        try await wait { store.canSendShortcut(automatic) }

        await fake.enqueue(.rejected("Dock unavailable"), for: type)
        guard case .failure(let rejection)? = await store.sendShortcut(park) else { return XCTFail("Expected robot rejection") }
        XCTAssertEqual(rejection.message, "Dock unavailable")
        XCTAssertFalse(rejection.isLocal)
        guard case .success? = await store.sendShortcut(automatic) else { return XCTFail("Expected charge request") }
        XCTAssertEqual(store.stateLabel, "대기")
        let sent = await fake.calls.compactMap { call -> Data? in
            if case .request(let name, let body) = call, name == type { return body }
            return nil
        }
        XCTAssertEqual(try sent.map { try Woosh_Robot_ExecTask(jsonUTF8Data: $0).type }, [.kParking, .kCharge])

        await fake.publish(.scene, body: Data(#"{"sceneName":"예시","mapId":2}"#.utf8))
        try await wait { store.currentMapID == "2" }
        let afterMapChange = await store.sendShortcut(park)
        XCTAssertNil(afterMapChange)
        await store.disconnect()
        await store.connect(host: "192.0.2.11", port: 5480)
        try await wait { store.state == .ready && store.currentMapID == "1" }
        let afterPeerChange = await store.sendShortcut(automatic)
        XCTAssertNil(afterPeerChange)
        let count = await fake.calls.filter { if case .request(let name, _) = $0 { return name == type }; return false }.count
        XCTAssertEqual(count, 2)
        await store.disconnect()
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Store did not receive the expected session event")
    }
}
