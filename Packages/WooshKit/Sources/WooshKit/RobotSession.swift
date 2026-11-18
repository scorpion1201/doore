import Foundation

/// Feed names come from the same schema as the request and response messages.
public enum RobotFeed: CaseIterable, RawRepresentable, Sendable {
    case robotInfo, navPath, costmapData, sceneData, setting, robotState, mode, poseSpeed
    case battery, network, scene, taskProc, deviceState, model, statusCode, abnormalCodes

    case buildMapData, scannerData, cameraData, rfRemoteController

    public var rawValue: String {
        switch self {
        case .robotInfo: return Woosh_Robot_RobotInfo.protoMessageName
        case .navPath: return Woosh_Robot_NavPath.protoMessageName
        case .costmapData: return Woosh_Robot_CostmapData.protoMessageName
        case .sceneData: return Woosh_Map_SceneData.protoMessageName
        case .setting: return Woosh_Robot_Setting.protoMessageName
        case .robotState: return Woosh_Robot_RobotState.protoMessageName
        case .mode: return Woosh_Robot_Mode.protoMessageName
        case .poseSpeed: return Woosh_Robot_PoseSpeed.protoMessageName
        case .battery: return Woosh_Robot_Battery.protoMessageName
        case .network: return Woosh_Robot_Network.protoMessageName
        case .scene: return Woosh_Robot_Scene.protoMessageName
        case .taskProc: return Woosh_Robot_TaskProc.protoMessageName
        case .deviceState: return Woosh_Robot_DeviceState.protoMessageName
        case .model: return Woosh_Robot_Model.protoMessageName
        case .statusCode: return Woosh_Robot_Count_StatusCode.protoMessageName
        case .abnormalCodes: return Woosh_Robot_Count_AbnormalCodes.protoMessageName
        case .buildMapData: return Woosh_Robot_BuildMapData.protoMessageName
        case .scannerData: return Woosh_Robot_ScannerData.protoMessageName
        case .cameraData: return Woosh_Robot_CameraData.protoMessageName
        case .rfRemoteController: return Woosh_Device_RfRemoteController.protoMessageName
        }
    }

    public init?(rawValue: String) {
        guard let feed = Self.byName[rawValue] else { return nil }
        self = feed
    }

    private static let byName = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0) })

    static let initialSync: [Self] = [.robotInfo, .navPath, .costmapData, .sceneData]
    static let onDemand: Set<Self> = [.buildMapData, .scannerData, .cameraData, .rfRemoteController]
    static let subscriptions = Set(allCases).subtracting(onDemand).subtracting([.robotInfo, .sceneData])
}

public enum SessionEvent: Sendable {
    /// Identifies the endpoint for the following connection attempt and its events.
    case peer(Endpoint)
    case stateChanged(ConnectionState)
    case snapshot(type: String, body: Data)
    case notification(type: String, body: Data)
}

public enum SessionError: Error, Equatable, LocalizedError {
    case rejected(String)
    case notReady
    case modeMismatch

    public var errorDescription: String? {
        if case .rejected(let message) = self { return message }
        return nil
    }
}

public actor RobotSession {
    /// One consumer (the app store) distributes these events to the feature stores.
    public nonisolated let events: AsyncStream<SessionEvent>
    private let output: AsyncStream<SessionEvent>.Continuation
    public private(set) var state: ConnectionState = .disconnected

    private let transport: any RobotTransport
    private let teleop: VelocityLoop
    private let sleep: @Sendable (Duration) async throws -> Void
    private var timeout: Duration = .seconds(30)
    private var endpoint: Endpoint?
    private var suspended = false
    private var connection = UUID()
    private var readerID = UUID()
    private var reader: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var subscriptionWork: Task<Void, Error>?
    private var desiredFeeds: Set<RobotFeed> = []
    private var activeFeeds: Set<RobotFeed> = []
    private var socketLost = false
    private var snapshot = RobotSnapshot()
    // At most one update per subscribed feed awaits the matching sync snapshot.
    private var duringSync: [(RobotFeed, Data)] = []

    public init(transport: any RobotTransport) {
        self.init(transport: transport, sleep: { try await Task.sleep(for: $0) })
    }

    init(transport: any RobotTransport, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.transport = transport
        self.teleop = VelocityLoop(transport: transport)
        self.sleep = sleep
        (events, output) = AsyncStream.makeStream(of: SessionEvent.self)
    }

    deinit {
        reader?.cancel()
        retry?.cancel()
        subscriptionWork?.cancel()
        output.finish()
    }

    /// Screen-owned topics survive a reconnect and are removed when the screen closes.
    public func setSubscription(_ feeds: Set<RobotFeed>, enabled: Bool) async throws {
        let onDemand = feeds.intersection(RobotFeed.onDemand)
        if enabled { desiredFeeds.formUnion(onDemand) } else { desiredFeeds.subtract(onDemand) }
        if state == .ready { try await reconcileSubscriptions(id: connection) }
    }

    public func setRequestTimeout(_ timeout: Duration) {
        if timeout > .zero { self.timeout = timeout }
    }

    public func connect(to endpoint: Endpoint) async throws {
        self.endpoint = endpoint
        suspended = false
        let id = invalidate(next: .connecting)
        do {
            try await closeSocket(id)
            try await establish(to: endpoint, id: id)
        } catch {
            guard connection == id else { throw CancellationError() }
            await disconnect()
            throw error
        }
    }

    public func disconnect() async {
        endpoint = nil
        suspended = false
        let id = invalidate(next: .disconnected)
        try? await closeSocket(id)
    }

    /// On iOS the endpoint survives backgrounding, but the socket does not.
    public func suspend() async {
        guard !suspended else { return }
        suspended = true
        let id = invalidate(next: .disconnected)
        try? await closeSocket(id)
    }

    public func resume() async throws {
        guard suspended else { return }
        suspended = false
        guard let endpoint else { return }
        let id = invalidate(next: .connecting)
        do {
            try await closeSocket(id)
            try await establish(to: endpoint, id: id)
        } catch {
            guard connection == id else { throw CancellationError() }
            startReconnect(to: endpoint)
            throw error
        }
    }

    public func perform(_ command: RobotCommand) async throws {
        guard state == .ready else { throw SessionError.notReady }
        guard snapshot.allows(command) else { throw SessionError.modeMismatch }
        _ = try await request(type: command.type, body: command.body, id: connection)
    }

    func readOnly(type: String, body: Data) async throws -> Data {
        guard state == .ready else { throw SessionError.notReady }
        return try await request(type: type, body: body, id: connection).body
    }

    public func refreshScene() async throws {
        guard state == .ready else { throw SessionError.notReady }
        try await read(.sceneData, id: connection)
    }

    public func teleoperate(_ velocity: RobotVelocity) async {
        guard state == .ready, snapshot.allowsMotion else {
            await teleop.stop()
            return
        }
        await teleop.update(velocity)
    }

    public func stopTeleoperation() async {
        await teleop.stop()
    }

    private func transition(to next: ConnectionState) {
        if next == .connecting, let endpoint { output.yield(.peer(endpoint)) }
        guard state != next else { return }
        state = next
        output.yield(.stateChanged(next))
    }

    /// Abandon all work owned by the old connection before any suspension point.
    private func invalidate(next: ConnectionState) -> UUID {
        connection = UUID()
        snapshot = RobotSnapshot()
        duringSync.removeAll()
        reader?.cancel()
        reader = nil
        subscriptionWork?.cancel()
        subscriptionWork = nil
        retry?.cancel()
        retry = nil
        transition(to: next)
        return connection
    }

    private func closeSocket(_ id: UUID) async throws {
        await teleop.stop()
        guard connection == id else { throw CancellationError() }
        await transport.disconnect()
        guard connection == id else { throw CancellationError() }
    }

    private func check(_ id: UUID) throws {
        guard connection == id else { throw CancellationError() }
        try Task.checkCancellation()
        if socketLost { throw TransportError.disconnected }
    }

    private func establish(to endpoint: Endpoint, id: UUID) async throws {
        socketLost = false
        snapshot = RobotSnapshot()
        duringSync.removeAll()
        try await transport.connect(to: endpoint)
        try check(id)
        let incoming = await transport.events
        try check(id)
        let streamID = UUID()
        readerID = streamID
        reader = Task { [weak self] in
            for await event in incoming {
                if Task.isCancelled { break }
                await self?.receive(event, id: id, streamID: streamID)
            }
        }
        let requested = desiredFeeds
        let topics = RobotFeed.subscriptions.union(requested)
        try await transport.setSubscription(Set(topics.map(\.rawValue)), enabled: true)
        try check(id)
        activeFeeds = requested
        transition(to: .syncing)
        for feed in RobotFeed.initialSync {
            try await read(feed, id: id)
        }
        try check(id)
        while activeFeeds != desiredFeeds {
            try await reconcileSubscriptions(id: id)
            try check(id)
        }
        // Topics may be published between subscription and the last initial reply.
        // Replay them after the snapshots so an older bulk response cannot undo a change.
        for (feed, body) in duringSync where isSubscribed(to: feed) {
            applyNotification(feed, body: body)
        }
        duringSync.removeAll()
        transition(to: .ready)
    }

    private func isSubscribed(to feed: RobotFeed) -> Bool {
        RobotFeed.subscriptions.contains(feed) || desiredFeeds.contains(feed)
    }

    private func reconcileSubscriptions(id: UUID) async throws {
        if let subscriptionWork {
            try await subscriptionWork.value
            return
        }
        guard activeFeeds != desiredFeeds else { return }
        let work = Task {
            defer { if connection == id { subscriptionWork = nil } }
            while activeFeeds != desiredFeeds {
                try check(id)
                let removed = activeFeeds.subtracting(desiredFeeds)
                let added = desiredFeeds.subtracting(activeFeeds)
                let enabling = removed.isEmpty
                let changes = enabling ? added : removed
                try await transport.setSubscription(Set(changes.map(\.rawValue)), enabled: enabling)
                try check(id)
                if enabling { activeFeeds.formUnion(changes) } else { activeFeeds.subtract(changes) }
            }
        }
        subscriptionWork = work
        try await work.value
    }

    private func request(type: String, body: Data, id: UUID) async throws -> Reply {
        try check(id)
        let reply: Reply
        do {
            reply = try await transport.request(type: type, body: body, timeout: timeout)
        } catch {
            // Do not report a delayed error from a socket the user has already replaced.
            try check(id)
            throw error
        }
        try check(id)
        guard reply.ok else { throw SessionError.rejected(reply.message) }
        return reply
    }

    private func read(_ feed: RobotFeed, id: UUID) async throws {
        let body: Data
        switch feed {
        case .sceneData:
            // Ask for the current scene reported by the robot, including an interleaved switch.
            let latest = duringSync.last(where: { $0.0 == .scene })
            let update = latest.flatMap { try? Woosh_Robot_Scene(jsonUTF8Data: $0.1) }
            let name = update?.sceneName ?? snapshot.sceneName ?? ""
            body = try Woosh_Map_SceneData.with { $0.name = name }.jsonUTF8Data()
        case .navPath:
            var message = Woosh_Robot_NavPath()
            if let number = snapshot.number.flatMap(UInt32.init) { message.robotID = number }
            body = try message.jsonUTF8Data()
        default:
            body = Data("{}".utf8)
        }
        let reply = try await request(type: feed.rawValue, body: body, id: id)
        try check(id)
        if feed == .robotInfo {
            snapshot.apply(feed, data: reply.body)
        }
        output.yield(.snapshot(type: feed.rawValue, body: reply.body))
    }

    private func applyNotification(_ feed: RobotFeed, body: Data) {
        switch feed {
        case .setting, .robotState, .mode, .poseSpeed, .battery, .network, .scene, .taskProc, .deviceState, .statusCode, .abnormalCodes:
            snapshot.apply(feed, data: body)
        default:
            break
        }
        output.yield(.notification(type: feed.rawValue, body: body))
    }

    private func receive(_ event: TransportEvent, id: UUID, streamID: UUID) async {
        guard connection == id, readerID == streamID else { return }
        switch event {
        case .notification(let type, let body):
            guard !socketLost, let feed = RobotFeed(rawValue: type),
                  isSubscribed(to: feed) else { return }
            if state == .ready {
                let wasAllowed = snapshot.allowsMotion
                applyNotification(feed, body: body)
                if wasAllowed && !snapshot.allowsMotion { await teleop.stop() }
            } else {
                duringSync.removeAll { $0.0 == feed }
                duringSync.append((feed, body))
            }
        case .stateChanged(.disconnected):
            socketLost = true
            if state == .ready, let endpoint { startReconnect(to: endpoint) }
        case .stateChanged:
            break
        }
    }

    private func startReconnect(to endpoint: Endpoint) {
        let id = invalidate(next: .reconnecting)
        retry = Task { [weak self] in
            await self?.reconnect(to: endpoint, id: id)
        }
    }

    private func reconnect(to endpoint: Endpoint, id: UUID) async {
        var delay = 1
        while connection == id && !Task.isCancelled {
            do {
                reader?.cancel()
                try await closeSocket(id)
                try await sleep(.seconds(delay))
                guard connection == id else { return }
                try Task.checkCancellation()
                transition(to: .connecting)
                try await establish(to: endpoint, id: id)
                retry = nil
                return
            } catch {
                guard connection == id && !Task.isCancelled else { return }
                transition(to: .reconnecting)
                delay = min(delay * 2, 10)
            }
        }
    }
}
