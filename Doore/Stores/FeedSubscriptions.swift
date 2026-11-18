import Foundation
import Observation
import WooshKit

/// Screen ownership is local to a window. The session gets the union of all requested topics.
@MainActor @Observable
final class FeedSubscriptions {
    private(set) var scan: LidarScan?
    private(set) var mapFrame: MapBuildFrame?
    private(set) var failures: Set<RobotFeed> = []

    private let session: RobotSession
    private let log: CommunicationLog
    @ObservationIgnored private var owners: [UUID: Set<RobotFeed>] = [:]
    @ObservationIgnored private var desired: Set<RobotFeed> = []
    @ObservationIgnored private var forwarded: Set<RobotFeed> = []
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var queued: [RobotFeed: Data] = [:]
    @ObservationIgnored private var decoding: [RobotFeed: UUID] = [:]

    init(session: RobotSession, log: CommunicationLog) {
        self.session = session
        self.log = log
    }

    func update(_ owner: UUID, wants feeds: Set<RobotFeed>) {
        owners[owner] = feeds.isEmpty ? nil : feeds
        let next = owners.values.reduce(into: Set<RobotFeed>()) { $0.formUnion($1) }
        for feed in desired.subtracting(next) { clear(feed) }
        desired = next
        guard updates == nil, forwarded != desired else { return }
        updates = Task { [weak self] in await self?.reconcile() }
    }

    private func reconcile() async {
        defer { updates = nil }
        while forwarded != desired {
            let remove = forwarded.subtracting(desired)
            let enable = remove.isEmpty
            let changes = enable ? desired.subtracting(forwarded) : remove
            do {
                try await session.setSubscription(changes, enabled: enable)
                failures.subtract(changes)
            } catch {
                if enable { failures.formUnion(changes.intersection(desired)) }
            }
            // The session stores this intent before its first suspension, even on a socket failure.
            if enable { forwarded.formUnion(changes) } else { forwarded.subtract(changes) }
        }
    }

    func resetFrames() {
        clear(.scannerData)
        clear(.buildMapData)
    }

    private func clear(_ feed: RobotFeed) {
        queued[feed] = nil
        decoding[feed] = nil
        failures.remove(feed)
        if feed == .scannerData { scan = nil }
        if feed == .buildMapData { mapFrame = nil }
    }

    /// Keep only the newest waiting frame while parsing a large protobuf body off the UI thread.
    func receive(_ feed: RobotFeed, data: Data) {
        guard desired.contains(feed) else { return }
        if decoding[feed] != nil { queued[feed] = data; return }
        let id = UUID()
        decoding[feed] = id
        Task {
            let result = await Task.detached(priority: .utility) { () -> Frame? in
                switch feed {
                case .scannerData: return (try? LidarScan(data: data)).map(Frame.scan)
                case .buildMapData: return (try? MapBuildFrame(data: data)).map(Frame.map)
                default: return nil
                }
            }.value
            guard decoding[feed] == id else { return }
            decoding[feed] = nil
            switch result {
            case .scan(let value): scan = value
            case .map(let value): mapFrame = value
            case nil: log.record("invalid \(feed.rawValue)")
            }
            if let next = queued.removeValue(forKey: feed) { receive(feed, data: next) }
        }
    }

    private enum Frame: Sendable {
        case scan(LidarScan)
        case map(MapBuildFrame)
    }
}
