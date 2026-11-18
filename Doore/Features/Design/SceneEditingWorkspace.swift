import Foundation
import Observation
import WooshKit

@MainActor @Observable
final class SceneEditingWorkspace {
    private(set) var source: LocalScene?
    private(set) var map: MapModel?
    private var rawScene: Data?
    private(set) var actionGroup = ""
    var draft = SceneDraft()
    var selection: UUID?
    var library: [LocalScene] = []
    var failure: String?
    var busy = false
    private var saved: SceneDraft.Snapshot?

    var hasUnsavedEdits: Bool { saved.map { $0 != draft.snapshot } ?? (draft.changedItemCount != 0) }

    func openSource(scene: SceneModel, map: MapModel, raw: Data, host: String, port: Int) {
        let details: SceneEditingDetails
        do { details = try SceneEditingDetails(sceneData: raw, mapID: map.id) }
        catch { failure = "장면 데이터를 읽지 못했습니다."; return }
        let items = map.stations.compactMap { station -> DraftItem? in
            guard let pose = station.pose else { return nil }
            let fields = details.stationProperties(number: station.number)
            return DraftItem(kind: .point, subtype: station.kind, points: [.init(x: pose.x, y: pose.y)],
                             number: station.number, description: station.description, heading: pose.theta,
                             arrival: fields.arrival, dockingChecks: fields.dockingChecks)
        }
        self.map = map
        rawScene = raw
        source = LocalScene(id: UUID(), host: host, port: port, scene: scene.name, mapID: map.id, mapName: map.name)
        selection = nil
        draft = SceneDraft(original: items + details.geometry, taskSets: details.taskSets)
        actionGroup = details.actionGroup
        saved = nil
    }

    func refresh() async {
        do { library = try await SceneDraftLibrary.shared.list() }
        catch { failure = "저장한 장면 목록을 읽지 못했습니다." }
    }

    func load(_ file: LocalScene) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let contents = try await SceneDraftLibrary.shared.read(file)
            let scene = try SceneModel(data: contents.source)
            guard let map = scene.map(id: file.mapID) else { throw CocoaError(.coderReadCorrupt) }
            let details = try SceneEditingDetails(sceneData: contents.source, mapID: map.id)
            self.map = map
            actionGroup = details.actionGroup
            rawScene = contents.source
            source = file
            selection = nil
            draft = SceneDraft(snapshot: contents.draft)
            saved = contents.draft
        } catch { failure = "저장한 장면을 열지 못했습니다." }
    }

    func save(backup: Bool) async {
        guard !busy, let source, let rawScene else { return }
        busy = true
        defer { busy = false }
        let file = LocalSceneFile(source: rawScene, draft: draft.snapshot, scene: source)
        do {
            try await SceneDraftLibrary.shared.save(file, backup: backup, replacing: saved)
            if self.source?.id == source.id { saved = file.draft }
            await refresh()
        } catch SceneDraftLibrary.LibraryError.changedInAnotherWindow {
            failure = "다른 창에서 장면이 변경되었습니다. 장면 라이브러리에서 다시 여세요."
        } catch { failure = "장면을 저장하지 못했습니다." }
    }

    func delete(_ file: LocalScene) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await SceneDraftLibrary.shared.delete(file)
            if source?.id == file.id {
                source = nil
                map = nil
                rawScene = nil
                actionGroup = ""
                draft = SceneDraft()
                saved = nil
                selection = nil
            }
            await refresh()
        } catch { failure = "장면을 삭제하지 못했습니다." }
    }
}
