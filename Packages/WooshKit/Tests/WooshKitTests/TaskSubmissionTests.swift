import Foundation
import XCTest
@testable import WooshKit

final class TaskSubmissionTests: XCTestCase {
    private func scene(document: String, group: Int32 = 9) throws -> SceneModel {
        var message = Woosh_Map_SceneData()
        message.name = "Example"
        message.actionGroup = document
        message.maps = [.with { map in
            map.id = 1
            map.name = "F1"
            map.markInfo.storages = [.with { $0.identity.no = "S1" }]
        }]
        message.taskInfo.repeatTasks = [.with { set in
            set.taskSet.base.id = -123
            set.taskSet.base.name = "Original"
            set.taskSet.tasks = [.with { $0.base.markNo = "S1"; $0.base.type = .kPick; $0.base.typeNo = group; $0.base.id = Int32.max; $0.consta.failEnd = true }]
        }]
        return try SceneModel(data: message.jsonUTF8Data())
    }

    private func task(group: Int32 = 9) -> StationTask {
        StationTask(station: "S1", kind: 1, direction: 1, group: group, wait: 7, custom: "example")
    }

    func testScopeAndCheckedReferences() throws {
        for absent in ["", "{}", "[]", "not JSON", "\"\""] {
            let model = try scene(document: absent)
            XCTAssertNil(TaskSubmission(scene: model, mapID: "1", tasks: [task()], destination: .single))
        }
        let model = try scene(document: "[{}]")
        XCTAssertNil(TaskSubmission(scene: model, mapID: "1", tasks: [task(group: 10)], destination: .single))
        let negative = try scene(document: "[{}]", group: -1)
        XCTAssertNil(TaskSubmission(scene: negative, mapID: "1", tasks: [task(group: -1)], destination: .single))
        XCTAssertNil(TaskSubmission(scene: model, mapID: "2", tasks: [task()], destination: .single))
        XCTAssertNil(TaskSubmission(scene: model, mapID: "1", tasks: [task()], destination: .predefined, name: "Original"))
    }

    func testTaskAndPresetSerialization() throws {
        let model = try scene(document: "[{}]")
        let single = try XCTUnwrap(TaskSubmission(scene: model, mapID: "1", tasks: [task()], destination: .single))
        let body = try Woosh_Robot_ExecTask(jsonUTF8Data: single.body)
        XCTAssertEqual(body.taskTypeNo, 9)
        XCTAssertEqual(body.markNo, "S1")
        XCTAssertEqual(body.direction, .kFeeding)
        let preset = try XCTUnwrap(TaskSubmission(scene: model, mapID: "1", tasks: [task()], destination: .predefined,
                                                  name: "New", repeats: -1))
        let repeatTask = try Woosh_Task_RepeatTask(jsonUTF8Data: preset.body)
        XCTAssertEqual(repeatTask.order, .kPut)
        XCTAssertEqual(repeatTask.times, -1)
        XCTAssertEqual(repeatTask.taskSet.base.id, 0)
        XCTAssertEqual(repeatTask.taskSet.tasks.first?.base.waitTime, 7)
        XCTAssertEqual(model.predefinedSets.first?.id, -123)
        XCTAssertFalse(single.allows(RobotSnapshot()))
    }

    func testCopyPreservesMetadataWithoutReusingPresetIdentity() throws {
        let model = try scene(document: "[{}]")
        let source = try XCTUnwrap(model.predefinedSets.first)
        let original = try XCTUnwrap(source.content.tasks.first)
        let copy = StationTask(copying: original, station: "S1", kind: 1, direction: 1, group: 9,
                               wait: 10, custom: Data())
        let command = try XCTUnwrap(TaskSubmission(scene: model, mapID: "1", tasks: [task(), copy],
                                                   destination: .predefined, name: "Edited", source: source))
        let set = try Woosh_Task_RepeatTask(jsonUTF8Data: command.body).taskSet
        XCTAssertEqual(set.base.name, "Edited")
        XCTAssertEqual(set.base.id, 0)
        XCTAssertEqual(set.tasks.map(\.base.id), [1, Int32.max])
        XCTAssertEqual(set.tasks.last?.consta.failEnd, true)
        XCTAssertEqual(set.tasks.last?.base.waitTime, 10)
        XCTAssertNil(TaskSubmission(scene: model, mapID: "1", tasks: [copy, copy],
                                    destination: .predefined, name: "Duplicate", source: source))
    }

    func testStepWireAndModeGate() throws {
        let invalid = RobotSettingChange.step(mode: 2, value: 0, speed: 0.3, angle: 0, avoid: true)
        let step = RobotSettingChange.step(mode: 2, value: 1, speed: 0.3, angle: 0, avoid: true)
        var snapshot = RobotSnapshot()
        XCTAssertFalse(step.allows(snapshot))
        XCTAssertTrue(snapshot.apply(.robotInfo, data: Data(#"{"state":2,"deviceState":{},"battery":{"chargeState":1}}"#.utf8)))
        XCTAssertFalse(invalid.allows(snapshot))
        XCTAssertTrue(step.allows(snapshot))
        let wire = try Woosh_Ros_CallAction(jsonUTF8Data: step.body)
        XCTAssertEqual(wire.stepControl.steps.first?.mode, .kRotate)
        XCTAssertEqual(wire.stepControl.avoid, 1)
        XCTAssertEqual(wire.stepControl.action, .kExecute)
        XCTAssertEqual(try Woosh_Ros_CallAction(jsonUTF8Data: RobotSettingChange.cancelStep.body).stepControl.action, .kCancel)
    }
}
