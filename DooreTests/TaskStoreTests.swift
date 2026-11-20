import XCTest
@testable import Doore

final class TaskStoreTests: XCTestCase {
    func testEditingAndReorderingKeepsSelectedTaskIdentity() {
        let draft = TaskStore()
        var first = TaskDraftItem(station: "A1")
        let second = TaskDraftItem(station: "A2")
        draft.save(first)
        draft.save(second)
        XCTAssertTrue(draft.move(second.id, to: first.id))
        XCTAssertEqual(draft.items.map(\.station), ["A2", "A1"])
        first.wait = 12
        draft.save(first)
        XCTAssertEqual(draft.selectedItem?.wait, 12)
        XCTAssertEqual(draft.items.count, 2)
        draft.deleteSelection()
        XCTAssertEqual(draft.items.map(\.station), ["A2"])
        XCTAssertNil(draft.selectedItem)
    }
}
