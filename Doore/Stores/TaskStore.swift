import Foundation
import Observation
import WooshKit

struct TaskDraftItem: Identifiable, Equatable {
    var id = UUID()
    var station: String
    var kind = "픽"
    var direction = "적재"
    var source: Woosh_Task_WooshTask?
    var group: Int32?
    var wait = 0
    var kindCode: Int { ["픽": 1, "주차": 2, "충전": 3, "운반": 4][kind] ?? 0 }
    var action: StationTask? {
        guard let group, let seconds = Int32(exactly: wait) else { return nil }
        let directionCode = ["적재": 1, "하역": 2][direction] ?? 0
        if let source {
            return StationTask(copying: source, station: station, kind: kindCode, direction: directionCode,
                               group: group, wait: seconds, custom: custom == String(decoding: source.base.custom, as: UTF8.self)
                                   ? source.base.custom : Data(custom.utf8))
        }
        return StationTask(station: station, kind: kindCode, direction: directionCode,
                           group: group, wait: seconds, custom: custom)
    }
    var custom = ""
}

@Observable final class TaskStore {
    var name = ""
    var repeats = "0"
    var items: [TaskDraftItem] = []
    var selectedID: UUID?
    var selectedItem: TaskDraftItem? { items.first { $0.id == selectedID } }
    let source: PredefinedSet?

    init(source: PredefinedSet? = nil) {
        self.source = source
        guard let source else { return }
        repeats = String(source.repeatCount ?? 0)
        items = source.content.tasks.map { original in
            var item = TaskDraftItem(station: original.base.markNo)
            item.source = original
            item.kind = [1: "픽", 2: "주차", 3: "충전", 4: "운반"][original.base.type.rawValue] ?? "—"
            item.direction = [1: "적재", 2: "하역"][original.base.direction.rawValue] ?? "—"
            item.group = original.base.typeNo
            item.wait = Int(original.base.waitTime)
            item.custom = String(decoding: original.base.custom, as: UTF8.self)
            return item
        }
    }

    func save(_ item: TaskDraftItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
        selectedID = item.id
    }

    func deleteSelection() {
        items.removeAll { $0.id == selectedID }
        selectedID = nil
    }

    func move(_ id: UUID, to destination: UUID) -> Bool {
        guard let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == destination }), from != to else { return false }
        items.insert(items.remove(at: from), at: to)
        return true
    }

    func submission(_ destination: TaskSubmission.Destination, scene: SceneModel?, map: MapModel?) -> TaskSubmission? {
        guard let scene, let map, let count = Int32(repeats), items.allSatisfy({ $0.action != nil }) else { return nil }
        return TaskSubmission(scene: scene, mapID: map.id, tasks: items.compactMap(\.action), destination: destination,
                              name: name, repeats: count, source: source)
    }
}
