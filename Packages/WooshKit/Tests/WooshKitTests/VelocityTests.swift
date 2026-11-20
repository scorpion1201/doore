import Foundation
import XCTest
@testable import WooshKit
import WooshKitTesting

final class VelocityTests: XCTestCase {
    private let endpoint = Endpoint(host: "192.0.2.7")
    private let forward = RobotVelocity(linear: 0.2, angular: 0)
    private let readyBody = Data("""
    {"state":"kIdle","deviceState":{},"battery":{"chargeState":"kNot"},
     "mode":{"ctrl":"kAuto","work":"kTaskMode"}}
    """.utf8)

    private func setup() async throws -> (RobotSession, FakeRobotTransport) {
        let fake = FakeRobotTransport(snapshots: [RobotFeed.robotInfo.rawValue: readyBody])
        let session = RobotSession(transport: fake)
        try await session.connect(to: endpoint)
        return (session, fake)
    }

    private func commands(_ fake: FakeRobotTransport) async throws -> [Woosh_Robot_Twist] {
        try await fake.calls.compactMap {
            guard case .command(let type, let data) = $0 else { return nil }
            XCTAssertEqual(type, Woosh_Robot_Twist.protoMessageName)
            return try Woosh_Robot_Twist(jsonUTF8Data: data)
        }
    }

    private func waitForFirstWrite(_ fake: FakeRobotTransport) async throws {
        for _ in 0..<100 {
            if try await !commands(fake).isEmpty { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The velocity loop never started")
    }

    func testHoldUsesLatestVelocityAndReleaseEndsWithTwoStops() async throws {
        let (session, fake) = try await setup()
        await session.teleoperate(forward)
        try await waitForFirstWrite(fake)
        for _ in 0..<50 { await session.teleoperate(.init(linear: 0.1, angular: 0.2)) }
        try await Task.sleep(for: .milliseconds(320))
        await session.stopTeleoperation()
        let sent = try await commands(fake)
        XCTAssertTrue((3...9).contains(sent.count - 2))
        XCTAssertEqual(sent.first?.linear, 0.2)
        XCTAssertEqual(sent.dropLast(2).last?.angular, 0.2)
        XCTAssertEqual(Array(sent.suffix(2)), [.init(), .init()])
        try await Task.sleep(for: .milliseconds(140))
        let resting = try await commands(fake)
        XCTAssertEqual(resting.count, sent.count)
    }

    func testBackgroundStopsBeforeDisconnectAndForegroundRequiresFreshInput() async throws {
        let (session, fake) = try await setup()
        await session.teleoperate(forward)
        try await waitForFirstWrite(fake)
        await session.suspend()
        try await session.resume()
        let count = try await commands(fake).count
        try await Task.sleep(for: .milliseconds(100))
        let sent = try await commands(fake)
        XCTAssertEqual(sent.count, count)
        XCTAssertEqual(Array(sent.suffix(2)), [.init(), .init()])
    }

    func testDisconnectStopsWhileSocketIsStillAvailable() async throws {
        let (session, fake) = try await setup()
        await session.teleoperate(forward)
        try await waitForFirstWrite(fake)
        await session.disconnect()
        let sent = try await commands(fake)
        XCTAssertEqual(Array(sent.suffix(2)), [.init(), .init()])
    }

    func testMotionGateRequiresKnownStateAndRejectsActiveTaskAndCharge() throws {
        var report = RobotSnapshot()
        XCTAssertFalse(report.allowsMotion)
        XCTAssertTrue(report.apply(.robotInfo, data: readyBody))
        XCTAssertTrue(report.allowsMotion)
        XCTAssertTrue(report.apply(.robotState, data: Data(#"{"state":4}"#.utf8)))
        XCTAssertFalse(report.allowsMotion)
        _ = report.apply(.taskProc, data: Data(#"{"state":"kPaused"}"#.utf8))
        XCTAssertTrue(report.allowsMotion)
        _ = report.apply(.battery, data: Data(#"{"chargeState":3}"#.utf8))
        XCTAssertFalse(report.allowsMotion)
    }

    func testSnapshotRecognizesRobotIdentityAndExactUnsignedStatusCode() {
        var report = RobotSnapshot()
        let body = Data(#"{"robotId":5,"genral":{"serialNumber":87},"state":"kIdle","statusCodes":{"scs":[{"code":"18446744073709551615","msg":"original message"}]},"future":{}}"#.utf8)
        XCTAssertTrue(report.apply(.robotInfo, data: body))
        XCTAssertEqual(report.number, "5")
        XCTAssertEqual(report.state, 2)
        XCTAssertEqual(report.statusCode, "18446744073709551615")
        XCTAssertEqual(report.statusMessage, "original message")
        XCTAssertFalse(report.apply(.robotState, data: Data(#"{"state":true}"#.utf8)))
        XCTAssertEqual(report.state, 2)
    }
}

extension VelocityTests {
    func testPoseResetUsesReportedMapAndRecordedOrQRRequest() throws {
        var state = RobotSnapshot()
        XCTAssertTrue(state.apply(.robotInfo, data: Data(#"{"state":1,"scene":{"mapId":17}}"#.utf8)))
        let pose = MapPose(x: -1.5, y: 2, theta: .pi)
        let request = RobotCommand.setPose(mapID: "17", pose: pose)
        XCTAssertTrue(state.allows(request))
        XCTAssertFalse(state.allows(.setPose(mapID: "18", pose: pose)))
        XCTAssertEqual(try Woosh_Robot_SetRobotPose(jsonUTF8Data: request.body).pose.x, -1.5)
        XCTAssertTrue(try Woosh_Robot_InitRobot(jsonUTF8Data: RobotCommand.initializeQR.body).isQrcode)
        XCTAssertTrue(try Woosh_Robot_InitRobot(jsonUTF8Data: RobotCommand.initializeInPlace.body).isRecord)
        _ = state.apply(.robotState, data: Data(#"{"state":"kTask"}"#.utf8))
        XCTAssertFalse(state.allows(request))
    }
}
