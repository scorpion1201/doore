import Foundation

public struct LocalScene: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let host: String
    public let port: Int
    public let scene: String
    public let mapID: String
    public let mapName: String

    public init(id: UUID = UUID(), host: String, port: Int, scene: String, mapID: String, mapName: String) {
        self.id = id
        self.host = host
        self.port = port
        self.scene = scene
        self.mapID = mapID
        self.mapName = mapName
    }
}

public struct LocalSceneFile: Codable, Sendable {
    public let source: Data
    public let draft: SceneDraft.Snapshot
    public let scene: LocalScene

    public init(source: Data, draft: SceneDraft.Snapshot, scene: LocalScene) {
        self.source = source
        self.draft = draft
        self.scene = scene
    }
}

public actor SceneDraftLibrary {
    public static let shared = SceneDraftLibrary()
    public enum LibraryError: Error { case changedInAnotherWindow }

    private let location: URL?

    public init(location: URL? = nil) { self.location = location }

    private func directory() throws -> URL {
        if let location {
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            return location
        }
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        let folder = documents.appendingPathComponent("Scenes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func url(for scene: LocalScene) throws -> URL {
        try directory().appendingPathComponent(scene.id.uuidString).appendingPathExtension("doorescene")
    }

    public func list() throws -> [LocalScene] {
        struct Header: Decodable { let scene: LocalScene }
        let urls = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
        return try urls.filter { $0.pathExtension == "doorescene" }.map { url in
            try PropertyListDecoder().decode(Header.self, from: Data(contentsOf: url, options: .mappedIfSafe)).scene
        }.sorted { ($0.scene, $0.mapName, $0.host) < ($1.scene, $1.mapName, $1.host) }
    }

    public func read(_ scene: LocalScene, backup: Bool = false) throws -> LocalSceneFile {
        let file = try url(for: scene)
        let raw = try Data(contentsOf: backup ? file.appendingPathExtension("backup") : file, options: .mappedIfSafe)
        return try PropertyListDecoder().decode(LocalSceneFile.self, from: raw)
    }

    public func save(_ file: LocalSceneFile, backup: Bool, replacing expected: SceneDraft.Snapshot? = nil) throws {
        let destination = try url(for: file.scene)
        if let expected {
            guard FileManager.default.fileExists(atPath: destination.path),
                  try read(file.scene).draft == expected else { throw LibraryError.changedInAnotherWindow }
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if backup {
            let old: Data
            if FileManager.default.fileExists(atPath: destination.path) {
                old = try Data(contentsOf: destination, options: .mappedIfSafe)
            } else {
                let baseline = SceneDraft(original: file.draft.original, taskSets: file.draft.originalSets)
                old = try encoder.encode(LocalSceneFile(source: file.source, draft: baseline.snapshot, scene: file.scene))
            }
            try old.write(to: destination.appendingPathExtension("backup"), options: .atomic)
        }
        try encoder.encode(file).write(to: destination, options: .atomic)
    }

    public func delete(_ scene: LocalScene) throws {
        let url = try url(for: scene)
        let backup = url.appendingPathExtension("backup")
        if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
        try FileManager.default.removeItem(at: url)
    }
}
