import Foundation
import Observation
import WooshKit

/// Reported directory and preview for the map screen. Selecting a preview never switches the robot.
@MainActor @Observable
final class SceneStore {
    private(set) var entries: [SceneListing] = []
    private(set) var scene: SceneModel?
    private(set) var sourceData: Data?
    private(set) var busy = false
    private(set) var failed = false
    private var readID = UUID()

    func clear() {
        readID = UUID()
        entries = []
        scene = nil
        sourceData = nil
        busy = false
        failed = false
    }

    func reload(_ robot: RobotStore, preferred: String? = nil) async {
        guard robot.state == .ready else { clear(); return }
        let id = begin()
        defer { if readID == id { busy = false } }
        do {
            let list = try await robot.session.sceneDirectory()
            guard current(id, robot) else { return }
            entries = list
            let names = Set(list.map(\.name))
            let name = [preferred, scene?.name, robot.snapshot.sceneName, list.first?.name]
                .compactMap { $0 }.first(where: names.contains)
            if let scene, !names.contains(scene.name) {
                self.scene = nil
                sourceData = nil
            }
            if let name { try await fetch(name, robot, id: id) }
        } catch {
            record(error, robot, id: id)
        }
    }

    func select(_ name: String, robot: RobotStore) async {
        guard robot.state == .ready, entries.contains(where: { $0.name == name }) else { return }
        let id = begin()
        defer { if readID == id { busy = false } }
        do { try await fetch(name, robot, id: id) }
        catch { record(error, robot, id: id) }
    }

    /// Keeps the old selection visible on rejection, then reads back any accepted edits.
    func apply(_ operation: SceneOperation, robot: RobotStore, preferred: String?) async {
        guard !busy, let scene, let entry = entries.first(where: { $0.name == scene.name }) else { return }
        switch operation {
        case let .renameScene(name, replacement):
            guard name == entry.name, !entries.contains(where: { $0.name == replacement }) else { return }
        case let .renameMap(name, map, replacement):
            guard name == entry.name, entry.maps.contains(map), !entry.maps.contains(replacement) else { return }
        case let .deleteScene(name):
            guard name == entry.name else { return }
        case let .deleteMap(name, map), let .useMap(name, map, _):
            guard name == entry.name, entry.maps.contains(map) else { return }
        }
        let id = begin()
        defer { if readID == id { busy = false } }
        guard await robot.perform(.sceneOperation(operation)), current(id, robot) else { return }
        await reload(robot, preferred: preferred)
    }

    private func begin() -> UUID {
        readID = UUID()
        busy = true
        failed = false
        return readID
    }

    private func current(_ id: UUID, _ robot: RobotStore) -> Bool {
        readID == id && robot.state == .ready && !Task.isCancelled
    }

    private func fetch(_ name: String, _ robot: RobotStore, id: UUID) async throws {
        let result = try await robot.session.sceneSource(named: name)
        if current(id, robot) {
            scene = result.scene
            sourceData = result.data
            robot.cacheScene(result.scene, data: result.data)
        }
    }

    private func record(_ error: Error, _ robot: RobotStore, id: UUID) {
        guard current(id, robot), !(error is CancellationError) else { return }
        failed = true
        robot.report(error)
    }
}
