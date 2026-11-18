import Foundation
import Observation
import WooshKit

struct ConnectionRecord: Codable, Hashable, Identifiable {
    let host: String
    let port: Int
    let name: String?
    let lastConnected: Date
    var id: Endpoint { Endpoint(host: host, port: port) }
}

@MainActor @Observable
final class SettingsStore {
    private let defaults: UserDefaults
    var language: String { didSet { defaults.set(language, forKey: "language") } }
    var timeoutSeconds: Int { didSet { defaults.set(timeoutSeconds, forKey: "timeoutSeconds") } }
    var linearSpeed: Double { didSet { defaults.set(linearSpeed, forKey: "linearSpeed") } }
    var angularSpeed: Double { didSet { defaults.set(angularSpeed, forKey: "angularSpeed") } }
    var driveMode: String { didSet { defaults.set(driveMode, forKey: "driveMode") } }
    var visibleLayers: Set<String> { didSet { defaults.set(visibleLayers.sorted(), forKey: "layers") } }
    private(set) var history: [ConnectionRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "language": "ko", "timeoutSeconds": 30, "linearSpeed": 0.2, "angularSpeed": 0.3,
            "driveMode": "세로", "layers": ["주행 금지", "교통 통제", "구역", "스테이션", "경로", "로봇"]
        ])
        language = defaults.string(forKey: "language") ?? "ko"
        timeoutSeconds = max(1, defaults.integer(forKey: "timeoutSeconds"))
        linearSpeed = defaults.double(forKey: "linearSpeed")
        angularSpeed = defaults.double(forKey: "angularSpeed")
        driveMode = defaults.string(forKey: "driveMode") ?? "세로"
        visibleLayers = Set(defaults.stringArray(forKey: "layers") ?? [])
        history = defaults.data(forKey: "connections").flatMap { try? JSONDecoder().decode([ConnectionRecord].self, from: $0) } ?? []
    }

    func remember(_ endpoint: Endpoint, name: String?) {
        let old = history.first { $0.id == endpoint }
        history.removeAll { $0.id == endpoint }
        history.insert(ConnectionRecord(host: endpoint.host, port: endpoint.port, name: name ?? old?.name,
                                        lastConnected: Date()), at: 0)
        saveHistory()
    }

    func removeConnection(_ record: ConnectionRecord) {
        history.removeAll { $0.id == record.id }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "connections") }
    }
}
