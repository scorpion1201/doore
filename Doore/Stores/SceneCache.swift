import Foundation
import WooshKit

/// The cache stores robot-reported scene JSON. It is optional and may be purged by the OS.
struct SceneCache: Sendable {
    private static let io = DispatchQueue(label: "Doore.SceneCache", qos: .utility)
    private let root: URL?

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Doore/Scenes", isDirectory: true)
    }

    private func file(robot: String, scene: String) -> URL? {
        guard let root, let id = UInt32(robot), String(id) == robot, !scene.isEmpty else { return nil }
        // Encode robot-controlled names, including slashes and dot components. Chunking
        // keeps each directory name below the filesystem's component length limit.
        // Lowercase hex is injective even on a case-insensitive volume.
        let digits = Array("0123456789abcdef".utf8)
        let key = String(decoding: scene.utf8.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }, as: UTF8.self)
        var directory = root.appendingPathComponent(robot, isDirectory: true)
        var remainder = key[...]
        while !remainder.isEmpty {
            let piece = remainder.prefix(96)
            directory.appendPathComponent(String(piece), isDirectory: true)
            remainder = remainder.dropFirst(piece.count)
        }
        return directory.appendingPathComponent("scene.json")
    }

    func store(_ data: Data, robot: String, scene: String) {
        guard let url = file(robot: robot, scene: scene) else { return }
        Self.io.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                // Storage pressure or an OS cache purge must not affect the live connection.
            }
        }
    }

    func load(robot: String, scene: String) async -> SceneModel? {
        guard let url = file(robot: robot, scene: scene) else { return nil }
        return await withCheckedContinuation { continuation in
            Self.io.async {
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      let parsed = try? SceneModel(data: data), parsed.name == scene else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: parsed)
            }
        }
    }
}
