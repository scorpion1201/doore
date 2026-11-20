import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class TaskSubmissionFeedbackTests: XCTestCase {
    func testRejectedTaskCanBeRetriedAndAnInFlightTaskIsSentOnlyOnce() async throws {
        var snapshots = FakeRobotTransport.exampleSnapshots
        let sceneKey = RobotFeed.sceneData.rawValue
        var scene = try Woosh_Map_SceneData(jsonUTF8Data: XCTUnwrap(snapshots[sceneKey]))
        scene.actionGroup = "[{}]"
        scene.taskInfo.repeatTasks = [.with {
            $0.taskSet.tasks = [.with { $0.base.markNo = "A1"; $0.base.type = .kPick; $0.base.typeNo = 9 }]
        }]
        snapshots[sceneKey] = try scene.jsonUTF8Data()
        let fake = FakeRobotTransport(snapshots: snapshots)
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let robot = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await robot.connect(host: "192.0.2.10", port: 5480)
        for _ in 0..<100 where robot.state != .ready { try await Task.sleep(for: .milliseconds(5)) }
        let submission = try XCTUnwrap(TaskSubmission(scene: XCTUnwrap(robot.scene), mapID: "1",
            tasks: [StationTask(station: "A1", kind: 1, direction: 1, group: 9, wait: 0, custom: "")], destination: .single))
        let command = RobotCommand.taskSubmission(submission)

        await fake.enqueue(.rejected("busy: [A1]"), for: command.type)
        guard case .failure(let refusal)? = await robot.request(command) else { return XCTFail("Expected rejection") }
        XCTAssertEqual(refusal.message, "busy: [A1]")
        XCTAssertFalse(refusal.isLocal)
        XCTAssertNil(robot.errorMessage)
        XCTAssertTrue(robot.canSubmit(submission))

        await fake.enqueue(.delayed(Data("{}".utf8), by: .milliseconds(100)), for: command.type)
        async let retry = robot.request(command)
        for _ in 0..<100 where robot.canSubmit(submission) { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertFalse(robot.canSubmit(submission))
        let duplicate = await robot.request(command)
        XCTAssertNil(duplicate)
        guard case .success? = await retry else { return XCTFail("Expected successful retry") }
        let calls = await fake.calls.filter { if case .request(let type, _) = $0 { type == command.type } else { false } }
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(robot.canSubmit(submission))
        XCTAssertEqual(robot.stateLabel, "대기")
        await robot.disconnect()
    }
}
