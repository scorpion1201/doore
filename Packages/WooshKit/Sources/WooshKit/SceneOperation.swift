import Foundation
import SwiftProtobuf

/// The Mobile map screen names its changes against a scene, including when renaming a map.
public enum SceneOperation: Sendable, Equatable {
    case renameScene(scene: String, to: String)
    case renameMap(scene: String, map: String, to: String)
    case deleteScene(scene: String)
    case deleteMap(scene: String, map: String)
    case useMap(scene: String, map: String, reset: Bool)

    private var message: any Message {
        switch self {
        case let .renameScene(scene, name):
            return Woosh_Map_Rename.with { $0.oldSceneName = scene; $0.newSceneName = name }
        case let .renameMap(scene, map, name):
            return Woosh_Map_Rename.with { $0.oldSceneName = scene; $0.oldMapName = map; $0.newMapName = name }
        case let .deleteScene(scene):
            return Woosh_Map_Delete.with { $0.sceneName = scene }
        case let .deleteMap(scene, map):
            return Woosh_Map_Delete.with { $0.sceneName = scene; $0.mapName = map }
        case let .useMap(scene, map, reset):
            return Woosh_Robot_SwitchMap.with { $0.sceneName = scene; $0.mapName = map; $0.userReset = reset }
        }
    }

    public var type: String { Swift.type(of: message).protoMessageName }

    public var body: Data {
        get throws { try message.jsonUTF8Data() }
    }

    public static func validNewName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "~_#="))
        return !name.isEmpty && name.rangeOfCharacter(from: allowed.inverted) == nil
    }

    public func allows(_ snapshot: RobotSnapshot) -> Bool {
        // The source requires a connection for these operations; RobotSession enforces readiness.
        // Never encode a missing map name: on Delete it selects the entire scene.
        switch self {
        case let .renameScene(scene, name):
            return !scene.isEmpty && name != scene && Self.validNewName(name)
        case let .renameMap(scene, map, name):
            return !scene.isEmpty && !map.isEmpty && name != map && Self.validNewName(name)
        case let .deleteScene(scene):
            return !scene.isEmpty
        case let .deleteMap(scene, map), let .useMap(scene, map, _):
            return !scene.isEmpty && !map.isEmpty
        }
    }
}

public struct SceneListing: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let maps: [String]
}

extension RobotSession {
    public func sceneDirectory() async throws -> [SceneListing] {
        let data = try await readOnly(type: Woosh_Map_SceneList.protoMessageName, body: Woosh_Map_SceneList().jsonUTF8Data())
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        let directory = try Woosh_Map_SceneList(jsonUTF8Data: data, options: options)
        var seen = Set<String>()
        return directory.scenes.compactMap { scene in
            guard !scene.name.isEmpty, seen.insert(scene.name).inserted else { return nil }
            return SceneListing(name: scene.name, maps: scene.maps)
        }
    }

    /// Returns the exact JSON source as well as its drawable view for a local editing copy.
    public func sceneSource(named name: String) async throws -> (scene: SceneModel, data: Data) {
        guard !name.isEmpty else { throw TransportError.invalidEnvelope }
        let query = Woosh_Map_SceneData.with { $0.name = name }
        let data = try await readOnly(type: Woosh_Map_SceneData.protoMessageName, body: query.jsonUTF8Data())
        let scene = try SceneModel(data: data)
        guard scene.name == name else { throw TransportError.invalidEnvelope }
        return (scene, data)
    }

    public func scenePreview(named name: String) async throws -> SceneModel {
        try await sceneSource(named: name).scene
    }
}
