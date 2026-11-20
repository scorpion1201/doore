import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class FeedSubscriptionsTests: XCTestCase {
    func testWindowsShareHeavyTopicsAndLastCloseDropsLateFrames() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        try await session.connect(to: Endpoint(host: "192.0.2.5"))
        let subscriptions = FeedSubscriptions(session: session, log: CommunicationLog())
        let one = UUID(), two = UUID()
        subscriptions.update(one, wants: [.scannerData])
        subscriptions.update(two, wants: [.scannerData])
        try await wait { await fake.calls.contains(.subscription([RobotFeed.scannerData.rawValue], enabled: true)) }
        subscriptions.update(one, wants: [])
        subscriptions.receive(.scannerData, data: Data(#"{"ranges":[1,2,3]}"#.utf8))
        try await wait { subscriptions.scan?.validSamples == 3 }

        subscriptions.update(two, wants: [])
        try await wait { await fake.calls.contains(.subscription([RobotFeed.scannerData.rawValue], enabled: false)) }
        subscriptions.receive(.scannerData, data: Data(#"{"ranges":[2]}"#.utf8))
        XCTAssertNil(subscriptions.scan)
        let calls = await fake.calls
        XCTAssertEqual(calls.filter { $0 == .subscription([RobotFeed.scannerData.rawValue], enabled: true) }.count, 1)
        XCTAssertEqual(calls.filter { $0 == .subscription([RobotFeed.scannerData.rawValue], enabled: false) }.count, 1)
        await session.disconnect()
    }

    func testRapidOnOffBeforeWorkerRunsDoesNotLeaveAnActiveTopic() async throws {
        let fake = FakeRobotTransport()
        let session = RobotSession(transport: fake)
        let subscriptions = FeedSubscriptions(session: session, log: CommunicationLog())
        let owner = UUID()
        subscriptions.update(owner, wants: [.scannerData, .buildMapData])
        subscriptions.update(owner, wants: [])
        try await session.connect(to: Endpoint(host: "192.0.2.6"))
        let calls = await fake.calls
        for case .subscription(let topics, _) in calls {
            XCTAssertFalse(topics.contains(RobotFeed.scannerData.rawValue))
            XCTAssertFalse(topics.contains(RobotFeed.buildMapData.rawValue))
        }
        await session.disconnect()
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected subscription or frame was not observed")
    }
}
