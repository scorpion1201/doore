import Foundation
import XCTest
@testable import WooshKit

final class SceneDraftTests: XCTestCase {
    private let point = DraftPoint(x: -2, y: 4)

    func testEditsCountObjectsRelativeToRobotCopy() throws {
        let station = DraftItem(kind: .point, subtype: "스테이션", points: [point], number: "A1")
        var draft = SceneDraft(original: [station])
        draft.move(station.id, dx: 1, dy: -3)
        draft.move(station.id, dx: 1, dy: 1)
        XCTAssertEqual(draft.changedItemCount, 1)
        XCTAssertEqual(draft.items.first?.points, [DraftPoint(x: 0, y: 2)])

        let field = DraftItem(kind: .field, subtype: "양방향", points: [point, .init(x: 0, y: 4), .init(x: 0, y: 2)])
        draft.put(field)
        XCTAssertEqual(draft.changedItemCount, 2)
        draft.delete(field.id)
        XCTAssertEqual(draft.changedItemCount, 1)
        draft.undo()
        XCTAssertEqual(draft.changedItemCount, 2)
        draft.redo()
        XCTAssertEqual(draft.changedItemCount, 1)
        draft.delete(station.id)
        XCTAssertEqual(draft.items, [])
        XCTAssertEqual(draft.changedItemCount, 1)

        let bytes = try JSONEncoder().encode(draft.snapshot)
        let reopened = SceneDraft(snapshot: try JSONDecoder().decode(SceneDraft.Snapshot.self, from: bytes))
        XCTAssertEqual(reopened.changedItemCount, 1)
        XCTAssertEqual(reopened.items, [])
        XCTAssertFalse(reopened.canUndo)
    }

    func testUndoBackToBaselineAndBranchDropsRedo() {
        let item = DraftItem(kind: .point, subtype: "충전기", points: [point])
        var draft = SceneDraft(original: [item])
        draft.put(item)
        draft.move(item.id, dx: .infinity, dy: 0)
        XCTAssertFalse(draft.canUndo)
        draft.delete(item.id)
        draft.undo()
        XCTAssertEqual(draft.changedItemCount, 0)
        draft.move(item.id, dx: -1, dy: 0)
        XCTAssertFalse(draft.canRedo)
    }

    func testReadGeometryAndEditExistingGuideWithoutCreatingDuplicate() throws {
        let source = Data(#"{"name":"Example","maps":[{"id":9,"fieldInfo":{"speedLimitFields":[{"navFiled":{"id":4,"maxSpeed":0.25,"capacity":2,"vertexs":[{},{"x":2},{"x":2,"y":3}]}}]},"pathInfo":{"monoPaths":[{"width":0.5,"allowAvoid":true,"path":[{},{"y":2}]}]}}]}"#.utf8)
        let details = try SceneEditingDetails(sceneData: source, mapID: "9")
        var draft = SceneDraft(original: details.geometry)
        XCTAssertEqual(draft.items.map(\.subtype), ["속도 제한", "단방향 경로"])
        XCTAssertEqual(draft.items[0].capacity, 2)
        XCTAssertEqual(draft.items[1].width, 0.5)
        draft.move(draft.items[1].id, dx: -1, dy: 2)
        XCTAssertEqual(draft.items.count, 2)
        XCTAssertEqual(draft.changedItemCount, 1)
        draft.undo()
        XCTAssertEqual(draft.changedItemCount, 0)
    }

    func testHitTestingUsesSegmentsIncludingClosingFieldEdge() {
        let triangle = DraftItem(kind: .field, subtype: "양방향", points: [
            .init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 4, y: 4)
        ])
        XCTAssertEqual(triangle.distance(to: .init(x: 2, y: 2)), 0, accuracy: 0.0001)
        XCTAssertEqual(triangle.distance(to: .init(x: 2, y: -2)), 2, accuracy: 0.0001)
    }
}
