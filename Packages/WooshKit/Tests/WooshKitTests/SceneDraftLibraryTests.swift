import Foundation
import XCTest
@testable import WooshKit

final class SceneDraftLibraryTests: XCTestCase {
    func testSaveBackupReopenUndoAndDeletePreservingSourceAndTaskMetadata() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = SceneDraftLibrary(location: dir)
        let source = Data(#"{"name":"Example","maps":[{"id":2,"name":"Floor"}],"actionGroup":"[]","taskInfo":{"repeatTasks":[{"times":2,"addr":44,"taskSet":{"base":{"id":8,"name":"Original","adapter":"keep"},"tasks":[{"base":{"markNo":"A1","custom":"AP8="}}]}}]},"unrecognized":"retained"}"#.utf8)
        let local = LocalScene(host: "192.0.2.8", port: 5480, scene: "Example", mapID: "2", mapName: "Floor")
        let details = try SceneEditingDetails(sceneData: source, mapID: "2")
        var draft = SceneDraft(taskSets: details.taskSets)
        var set = try XCTUnwrap(draft.taskSets.first)
        set.content.base.name = "Changed"
        draft.put(set)
        XCTAssertEqual(draft.changedItemCount, 1)
        try await library.save(.init(source: source, draft: draft.snapshot, scene: local), backup: true)

        let backup = try await library.read(local, backup: true)
        XCTAssertEqual(backup.draft.taskSets.first?.content.base.name, "Original")
        let persisted = try await library.read(local)
        XCTAssertEqual(persisted.source, source)
        var reopened = SceneDraft(snapshot: persisted.draft)
        XCTAssertEqual(reopened.taskSets.first?.content.base.name, "Changed")
        XCTAssertEqual(reopened.taskSets.first?.content.base.adapter, "keep")
        XCTAssertEqual(reopened.taskSets.first?.repeatInfo?.addr, 44)
        XCTAssertEqual(reopened.taskSets.first?.content.tasks.first?.base.custom, Data([0, 255]))
        reopened.deleteTaskSet(set.id)
        reopened.undo()
        XCTAssertEqual(reopened.taskSets, draft.taskSets)
        reopened.redo()
        try await library.save(.init(source: source, draft: reopened.snapshot, scene: local), backup: true)
        do {
            try await library.save(persisted, backup: false, replacing: persisted.draft)
            XCTFail("A stale open document must not overwrite a newer revision")
        } catch SceneDraftLibrary.LibraryError.changedInAnotherWindow { }
        let secondBackup = try await library.read(local, backup: true)
        XCTAssertEqual(secondBackup.draft, persisted.draft)
        let list = try await library.list()
        XCTAssertEqual(list, [local])
        try await library.delete(local)
        let empty = try await library.list()
        XCTAssertTrue(empty.isEmpty)
    }
}
