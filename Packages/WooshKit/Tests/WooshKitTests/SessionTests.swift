import Foundation
import XCTest
@testable import WooshKit
import WooshKitTesting

final class SessionTests: XCTestCase {
    private let endpoint = Endpoint(host: "192.0.2.1")
    private let syncOrder = [
        "woosh.robot.RobotInfo", "woosh.robot.NavPath", "woosh.robot.CostmapData", "woosh.map.SceneData"
    ]

    func testFakeFloorAndLiveReportDecodeWithRestoredMessages() throws {
        let data = FakeRobotTransport.exampleSnapshots
        let report = try Woosh_Robot_RobotInfo(jsonUTF8Data: XCTUnwrap(data[RobotFeed.robotInfo.rawValue]))
        let scene = try Woosh_Map_SceneData(jsonUTF8Data: XCTUnwrap(data[RobotFeed.sceneData.rawValue]))
        let path = try Woosh_Robot_NavPath(jsonUTF8Data: XCTUnwrap(data[RobotFeed.navPath.rawValue]))
        let activeMap = try XCTUnwrap(scene.maps.first { $0.id == report.scene.mapID })
        XCTAssertEqual(activeMap.markInfo.storages.count, 2)
        XCTAssertTrue(activeMap.mapPng.starts(with: [137, 80, 78, 71]))
        XCTAssertEqual(path.path.poses.count, 2)
    }

    func testSubscribeThenInitialSyncInMobileOrder() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)

        let calls = await fake.calls
        XCTAssertEqual(calls.count, 6)
        XCTAssertEqual(calls.first, .connect)
        guard case let .subscription(topics, enabled) = calls.dropFirst().first else {
            return XCTFail("Subscription must precede every sync request")
        }
        XCTAssertTrue(enabled)
        XCTAssertEqual(topics.count, 14)
        XCTAssertTrue(topics.contains("woosh.robot.PoseSpeed"))
        XCTAssertFalse(topics.contains("woosh.robot.ScannerData"))
        let requests = calls.compactMap { call -> (String, Data)? in
            guard case .request(let type, let body) = call else { return nil }
            return (type, body)
        }
        XCTAssertEqual(requests.map { $0.0 }, syncOrder)
        XCTAssertEqual(try Woosh_Robot_NavPath(jsonUTF8Data: requests[1].1).robotID, 1)
        XCTAssertEqual(try Woosh_Map_SceneData(jsonUTF8Data: requests[3].1).name, "예시")

        await session.disconnect()
        let events = await statesAndSnapshots(session, until: .disconnected)
        XCTAssertEqual(events.states, [.connecting, .syncing, .ready, .disconnected])
        XCTAssertEqual(events.snapshots, syncOrder)
    }

    func testFailedSyncPreservesRobotMessageAndNeverEnablesCommands() async {
        let fake = FakeRobotTransport()
        await fake.enqueue(.rejected("scene unavailable"), for: RobotFeed.sceneData.rawValue)
        let session = RobotSession(transport: fake)
        do {
            try await session.connect(to: endpoint)
            XCTFail("Expected the robot's rejection")
        } catch {
            XCTAssertEqual(error as? SessionError, .rejected("scene unavailable"))
            XCTAssertEqual(error.localizedDescription, "scene unavailable")
        }
        let events = await statesAndSnapshots(session, until: .disconnected)
        XCTAssertFalse(events.states.contains(.ready))
        XCTAssertEqual(events.snapshots, Array(syncOrder.prefix(3)))
    }

    func testTimeoutAndRejectionKeepReadyConnection() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)
        await fake.enqueue(.timeout, for: RobotFeed.sceneData.rawValue)
        do {
            try await session.refreshScene()
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? TransportError, .timeout)
        }
        await fake.enqueue(.rejected("busy"), for: RobotFeed.sceneData.rawValue)
        do {
            try await session.refreshScene()
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? SessionError, .rejected("busy"))
        }
        try await session.refreshScene()
        let state = await session.state
        XCTAssertEqual(state, .ready)
        let calls = await fake.calls
        XCTAssertEqual(calls.filter { $0 == .connect }.count, 1)
    }

    func testDroppedConnectionRetriesWithCappedBackoffThenFullyResyncs() async throws {
        let fake = FakeRobotTransport()
        let delays = DelayRecorder()
        let session = RobotSession(transport: fake, sleep: { await delays.append($0) })
        try await session.connect(to: endpoint)
        await fake.failConnections(5)
        await fake.dropConnection()

        let resynced = await eventually {
            let calls = await fake.calls
            let state = await session.state
            return calls.filter { $0 == .connect }.count == 7 && state == .ready
        }
        XCTAssertTrue(resynced)
        let waits = await delays.values
        XCTAssertEqual(waits, [1, 2, 4, 8, 10, 10].map { .seconds($0) })
        let calls = await fake.calls
        let requests: [String] = calls.compactMap {
            if case .request(let type, _) = $0 { return type }
            return nil
        }
        XCTAssertEqual(requests, syncOrder + syncOrder)
        XCTAssertEqual(calls.filter { if case .subscription = $0 { return true }; return false }.count, 2)
    }

    func testForegroundResyncsButIntentionalDisconnectStaysDisconnected() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)
        await session.suspend()
        do {
            try await session.refreshScene()
            XCTFail("Should reject a request in the background")
        } catch {
            XCTAssertEqual(error as? SessionError, .notReady)
        }
        try await session.resume()
        try await session.resume()
        let foreground = await session.state
        XCTAssertEqual(foreground, .ready)
        await session.disconnect()
        await session.suspend()
        try await session.resume()
        let state = await session.state
        XCTAssertEqual(state, .disconnected)
        let calls = await fake.calls
        XCTAssertEqual(calls.filter { $0 == .connect }.count, 2)
        let requests = calls.compactMap { call -> String? in
            guard case .request(let type, _) = call else { return nil }
            return type
        }
        XCTAssertEqual(requests, syncOrder + syncOrder)
    }

    func testEachReadyEventBelongsToTheAnnouncedPeer() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        let second = Endpoint(host: "192.0.2.2")
        try await session.connect(to: endpoint)
        try await session.connect(to: second)
        await session.disconnect()

        var peer: Endpoint?
        var ready: [Endpoint] = []
        for await event in session.events {
            switch event {
            case .peer(let endpoint): peer = endpoint
            case .stateChanged(.ready): ready.append(try XCTUnwrap(peer))
            case .stateChanged(.disconnected): break
            default: continue
            }
            if case .stateChanged(.disconnected) = event { break }
        }
        XCTAssertEqual(ready, [endpoint, second])
    }

    func testReplacingConnectionDiscardsAnOutstandingSceneReply() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)
        let oldScene = Data(#"{"name":"old","maps":[]}"#.utf8)
        await fake.enqueue(.delayed(oldScene, by: .milliseconds(100)), for: RobotFeed.sceneData.rawValue)
        let reading = Task { try await session.refreshScene() }
        let waiting = await eventually {
            let calls = await fake.calls
            return calls.filter { if case .request("woosh.map.SceneData", _) = $0 { return true }; return false }.count == 2
        }
        XCTAssertTrue(waiting)
        try await session.connect(to: Endpoint(host: "192.0.2.2"))
        do {
            try await reading.value
            XCTFail("Obsolete reply must be discarded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let state = await session.state
        XCTAssertEqual(state, .ready)
    }

    func testTaskProgressChangesComeFromNotifications() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)
        let received = expectation(description: "Executing and paused notifications")
        let listener = Task {
            var states: [Int] = []
            for await event in session.events {
                guard case .notification("woosh.robot.TaskProc", let body) = event else { continue }
                let progress = try Woosh_Robot_TaskProc(jsonUTF8Data: body)
                states.append(progress.state.rawValue)
                if states.count == 2 { received.fulfill(); break }
            }
            return states
        }

        await fake.replayTask(paused: false)
        await fake.replayTask(paused: true)
        await fulfillment(of: [received], timeout: 2)
        listener.cancel()
        let states = try await listener.value
        XCTAssertEqual(states, [3, 4])
    }

    func testScreenSubscriptionsSurviveDropAndAreRemovedWhenScreenCloses() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake, sleep: { _ in })
        try await session.setSubscription([.scannerData], enabled: true)
        try await session.connect(to: endpoint)
        try await session.setSubscription([.buildMapData], enabled: true)
        try await session.setSubscription([.scannerData], enabled: false)
        await fake.dropConnection()
        let resynced = await eventually {
            let calls = await fake.calls
            let state = await session.state
            return calls.filter { $0 == .connect }.count == 2 && state == .ready
        }
        XCTAssertTrue(resynced)
        let subscriptions = await fake.calls.compactMap { call -> Set<String>? in
            if case .subscription(let topics, enabled: true) = call { return topics }
            return nil
        }
        XCTAssertEqual(subscriptions.count, 3)
        XCTAssertTrue(subscriptions.first?.contains(RobotFeed.scannerData.rawValue) == true)
        XCTAssertTrue(subscriptions.last?.contains(RobotFeed.buildMapData.rawValue) == true)
        XCTAssertFalse(subscriptions.last?.contains(RobotFeed.scannerData.rawValue) == true)
        try await session.setSubscription([.buildMapData], enabled: false)
        let last = await fake.calls.last
        XCTAssertEqual(last, .subscription([RobotFeed.buildMapData.rawValue], enabled: false))
    }

    func testIncomingModeOverridesInitialBulkSnapshot() async throws {
        let fake = FakeRobotTransport()
        let info = try XCTUnwrap(FakeRobotTransport.exampleSnapshots[RobotFeed.robotInfo.rawValue])
        await fake.enqueue(.delayed(info, by: .milliseconds(100)), for: RobotFeed.robotInfo.rawValue)
        let session = RobotSession(transport: fake)
        let connecting = Task { try await session.connect(to: endpoint) }
        let waitingOnBulkSnapshot = await eventually {
            let calls = await fake.calls
            return calls.contains(.request(type: RobotFeed.robotInfo.rawValue, body: Data("{}".utf8)))
        }
        XCTAssertTrue(waitingOnBulkSnapshot)
        await fake.publish(.mode, body: Data(#"{"ctrl":2,"work":1}"#.utf8))
        try await connecting.value
        do {
            try await session.perform(.workMode(2))
            XCTFail("Manual control mode must survive the initial bulk snapshot")
        } catch {
            XCTAssertEqual(error as? SessionError, .modeMismatch)
        }
        let calls = await fake.calls
        XCTAssertFalse(calls.contains { if case .request("woosh.robot.SwitchWorkMode", _) = $0 { return true }; return false })
    }

    func testChargingNotificationStopsActiveMotionAndBlocksFurtherInput() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)
        let velocity = RobotVelocity(linear: 0.1, angular: 0)
        await session.teleoperate(velocity)
        let moving = await eventually { await self.linearSpeeds(fake).contains(0.1) }
        XCTAssertTrue(moving)

        await fake.publish(.battery, body: Data(#"{"chargeState":3,"power":82}"#.utf8))
        let stopped = await eventually { Array(await self.linearSpeeds(fake).suffix(2)) == [0, 0] }
        XCTAssertTrue(stopped)
        let before = await linearSpeeds(fake)
        await session.teleoperate(velocity)
        try await Task.sleep(for: .milliseconds(100))
        let after = await linearSpeeds(fake)
        XCTAssertEqual(before, after)
    }

    private func linearSpeeds(_ fake: FakeRobotTransport) async -> [Double] {
        let calls = await fake.calls
        return calls.compactMap { call in
            guard case .command("woosh.robot.Twist", let body) = call else { return nil }
            return (try? JSONDecoder().decode([String: Double].self, from: body))?["linear"]
        }
    }

    private func statesAndSnapshots(_ session: RobotSession, until end: ConnectionState) async
        -> (states: [ConnectionState], snapshots: [String]) {
        let received = expectation(description: "State reached")
        let listener = Task {
            var states: [ConnectionState] = []
            var snapshots: [String] = []
            for await event in session.events {
                switch event {
                case .stateChanged(let state): states.append(state)
                case .snapshot(let type, _): snapshots.append(type)
                case .notification, .peer: break
                }
                if states.last == end { received.fulfill(); break }
            }
            return (states, snapshots)
        }
        await fulfillment(of: [received], timeout: 2)
        listener.cancel()
        return await listener.value
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }
}

private actor DelayRecorder {
    var values: [Duration] = []
    func append(_ delay: Duration) { values.append(delay) }
}
