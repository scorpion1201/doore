import Foundation
import Observation
import WooshKit

struct RobotRequestFailure: Error, Equatable {
    let message: String
    let isLocal: Bool

    init?(_ error: Error) {
        if error is CancellationError { return nil }
        if case SessionError.rejected(let reason) = error, !reason.isEmpty {
            message = reason
            isLocal = false
        } else {
            message = error as? TransportError == .timeout ? "요청 시간이 초과되었습니다." : "요청에 실패했습니다. 로봇 연결을 확인하세요."
            isLocal = true
        }
    }
}

@MainActor @Observable
final class RobotStore {
    let settings: SettingsStore
    let session: RobotSession
    let log: CommunicationLog
    let feeds: FeedSubscriptions
    private let sceneCache: SceneCache
    @ObservationIgnored private var cacheRead: Task<Void, Never>?
    private(set) var syncingMapPreview: MapModel?
    @ObservationIgnored private var observation: Task<Void, Never>?
    private var endpoint: Endpoint?
    private var reportedEndpoint: Endpoint?
    private var pendingCommandTypes: Set<String> = []
    private var connectionID = UUID()
    private var foreground = true
    private(set) var state: ConnectionState = .disconnected
    private(set) var snapshot = RobotSnapshot()
    private(set) var scene: SceneModel?
    private(set) var sceneData: Data?
    var pose: MapPose? { snapshot.pose }
    private(set) var navPath: [MapPose] = []
    var errorMessage: String?
    var errorMessageIsLocal = true
    private var blockedWindows: Set<UUID> = []
    var showConnect = false

    init(settings: SettingsStore, session: RobotSession? = nil, sceneCache: SceneCache = SceneCache()) {
        self.sceneCache = sceneCache
        self.settings = settings
        let log = CommunicationLog()
        self.log = log
        self.session = session ?? RobotSession(transport: WebSocketTransport(credentials: { KeychainCredentials.read($0) }) {
            direction, sequence, type in
            Task { @MainActor in log.record("\(direction) \(sequence) \(type)") }
        })
        feeds = FeedSubscriptions(session: self.session, log: log)
    }

    deinit {
        observation?.cancel()
        cacheRead?.cancel()
    }

    var name: String? { snapshot.name }
    var number: String? { snapshot.number }
    var host: String? { endpoint?.host }
    var port: Int? { endpoint?.port }
    var currentMapID: String? { snapshot.mapID }
    var poseMapID: String? { snapshot.poseMapID }
    var activeMap: MapModel? { scene?.name == snapshot.sceneName ? scene?.map(id: currentMapID) : nil }
    var aboutLogURL: URL? { log.url }
    var battery: Int? { snapshot.battery }
    var isCharging: Bool? { snapshot.charging }
    var isEmergencyStopped: Bool? { snapshot.emergencyStopped }
    var isPositionConfirmed: Bool? { snapshot.software.map { $0 & 1 != 0 } }
    var hasDispatchConnection: Bool? { snapshot.software.map { $0 & 2 != 0 } }
    var isLoaded: Bool? { snapshot.software.map { $0 & 4 != 0 } }
    var isOccupied: Bool? { snapshot.software.map { $0 & 8 != 0 } }
    var hasWiFi: Bool? { snapshot.wifiStrength.map { $0 > 0 } }
    var statusMessage: String? { snapshot.statusMessage }
    var statusCode: String? { snapshot.statusCode }
    var taskDestination: String? { snapshot.destination }
    var canTeleoperate: Bool {
        foreground && state == .ready && reportedEndpoint != nil && reportedEndpoint == endpoint &&
            snapshot.allowsMotion && blockedWindows.isEmpty
    }

    private func label(_ value: Int?, _ labels: [String]) -> String? {
        guard let value, value > 0, labels.indices.contains(value) else { return nil }
        return labels[value]
    }
    var stateLabel: String? {
        label(snapshot.state, ["", "미초기화", "대기", "주차 중", "작업 중", "경고", "고장", "추종", "충전 중", "지도 작성 중"])
    }
    var robotStateLabel: String? { stateLabel }
    var controlModeLabel: String? { label(snapshot.controlMode, ["", "자동", "수동", "정비"]) }
    var workModeLabel: String? { label(snapshot.workMode, ["", "배치", "작업", "관제"]) }
    var taskStateLabel: String? {
        label(snapshot.taskState, ["", "초기", "준비", "실행 중", "일시정지", "동작 대기", "작업 대기", "완료", "취소", "실패"])
    }
    var taskTypeLabel: String? { label(snapshot.taskType, ["", "픽", "주차", "충전", "운반"]) }
    var actionLabel: String? { label(snapshot.action, ["", "주행", "스텝 제어", "도킹 진입", "도킹 퇴출", "운반", "대기", "충전"]) }

    func start() async {
        guard observation == nil else { return }
        observe()
        if foreground, let last = settings.history.first { await connect(host: last.host, port: last.port) }
    }

    private func observe() {
        guard observation == nil else { return }
        let events = session.events
        observation = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { return }
                self?.receive(event)
            }
        }
    }

    private func receive(_ event: SessionEvent) {
        switch event {
        case .peer(let peer):
            reportedEndpoint = peer
        case .stateChanged(let next):
            state = next
            if next != .syncing { discardCachedPreview() }
            log.record("state \(next.rawValue)")
            if [.connecting, .disconnected, .reconnecting].contains(next) {
                feeds.resetFrames()
                snapshot = RobotSnapshot()
                scene = nil
                sceneData = nil
                pendingCommandTypes.removeAll()
                if next == .reconnecting { connectionID = UUID() }
                navPath = []
                motionGeneration = UUID()
            } else if next == .ready, let endpoint, reportedEndpoint == endpoint {
                settings.remember(endpoint, name: snapshot.name)
                errorMessage = nil
            }
        case .snapshot(let type, let data), .notification(let type, let data):
            guard let feed = RobotFeed(rawValue: type) else { return }
            if feed == .scannerData || feed == .buildMapData {
                log.record("received \(type)")
                feeds.receive(feed, data: data)
                return
            }
            let previousScene = snapshot.sceneName
            let previousMap = snapshot.mapID
            guard snapshot.apply(feed, data: data) else { log.record("invalid \(type)"); return }
            log.record("received \(type)")
            switch feed {
            case .scene:
                guard previousScene != snapshot.sceneName || previousMap != snapshot.mapID else { break }
                // NavPath carries no map ID. A new floor or scene needs a fresh path.
                navPath.removeAll()
                if previousScene != snapshot.sceneName, scene?.name != snapshot.sceneName {
                    scene = nil
                    sceneData = nil
                }
                loadCachedPreview()
                if state == .ready {
                    let id = connectionID
                    Task {
                        do { try await session.refreshScene() }
                        catch { if id == connectionID { report(error) } }
                    }
                }
            case .sceneData:
                discardCachedPreview()
                do {
                    let loaded = try SceneModel(data: data)
                    guard snapshot.sceneName == nil || loaded.name == snapshot.sceneName else {
                        log.record("obsolete \(type)")
                        return
                    }
                    scene = loaded
                    sceneData = data
                    cacheScene(loaded, data: data)
                }
                catch { scene = nil; sceneData = nil; log.record("invalid \(type)") }
            case .navPath: navPath = MapPose.path(data: data)
            case .robotInfo:
                loadCachedPreview()
            default: break
            }
        }
    }

    func cacheScene(_ scene: SceneModel, data: Data) {
        if let number { sceneCache.store(data, robot: number, scene: scene.name) }
    }

    private func discardCachedPreview() {
        cacheRead?.cancel()
        cacheRead = nil
        syncingMapPreview = nil
    }

    private func loadCachedPreview() {
        discardCachedPreview()
        guard state == .syncing, scene == nil, let number, let name = snapshot.sceneName,
              let mapID = currentMapID else { return }
        let ticket = connectionID
        cacheRead = Task { [weak self, sceneCache] in
            let cached = await sceneCache.load(robot: number, scene: name)
            guard !Task.isCancelled, let self, connectionID == ticket, state == .syncing,
                  scene == nil, self.number == number, snapshot.sceneName == name,
                  currentMapID == mapID else { return }
            syncingMapPreview = cached?.map(id: mapID)
        }
    }

    func connect(host: String, port: Int) async {
        let destination = Endpoint(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port)
        guard destination.isValid else { errorMessageIsLocal = true; errorMessage = "올바른 IP 주소와 포트를 입력하세요."; return }
        observe()
        connectionID = UUID()
        let id = connectionID
        endpoint = destination
        errorMessage = nil
        await updateTimeout()
        guard foreground, connectionID == id else { return }
        do {
            try await session.connect(to: destination)
        } catch {
            if connectionID == id { report(error) }
        }
    }

    func retry() async {
        if let endpoint { await connect(host: endpoint.host, port: endpoint.port) }
        else { showConnect = true }
    }

    func disconnect() async {
        connectionID = UUID()
        endpoint = nil
        errorMessage = nil
        motionGeneration = UUID()
        await session.disconnect()
    }

    func setActive(_ active: Bool) async {
        guard foreground != active else { return }
        foreground = active
        motionGeneration = UUID()
        if active {
            do { try await session.resume() } catch { report(error) }
        } else {
            connectionID = UUID()
            await session.suspend()
        }
    }

    func updateTimeout() async {
        await session.setRequestTimeout(.seconds(max(1, settings.timeoutSeconds)))
    }

    @discardableResult
    func perform(_ command: RobotCommand) async -> Bool {
        switch await request(command) {
        case .success?: return true
        case .failure(let failure)?: report(failure); return false
        case nil: return false
        }
    }

    func canSubmit(_ submission: TaskSubmission?) -> Bool {
        guard let submission else { return false }
        return foreground && state == .ready && reportedEndpoint == endpoint &&
            submission.allows(snapshot) && !pendingCommandTypes.contains(submission.type)
    }

    func request(_ command: RobotCommand) async -> Result<Void, RobotRequestFailure>? {
        guard foreground, state == .ready, reportedEndpoint == endpoint, snapshot.allows(command),
              pendingCommandTypes.insert(command.type).inserted else { return nil }
        let id = connectionID
        defer { if id == connectionID { pendingCommandTypes.remove(command.type) } }
        do {
            try await session.perform(command)
            return connectionID == id ? .success(()) : nil
        } catch {
            guard connectionID == id, let failure = RobotRequestFailure(error) else { return nil }
            return .failure(failure)
        }
    }

    struct PendingTaskControl: Equatable {
        let control: TaskControl
        fileprivate let target: TaskControlTarget
        fileprivate let connection: UUID
    }

    func prepareControl(_ control: TaskControl) -> PendingTaskControl? {
        guard foreground, state == .ready, let target = snapshot.target(for: control),
              snapshot.allows(.taskControl(control)) else { return nil }
        return PendingTaskControl(control: control, target: target, connection: connectionID)
    }

    func controlTask(_ pending: PendingTaskControl) async {
        guard pending.connection == connectionID else { return }
        await perform(.taskControl(pending.control, target: pending.target))
    }
    func switchWorkMode(_ mode: Int) async { await perform(.workMode(mode)) }
    func buildMap(_ operation: MapBuildOperation, name: String) async {
        await perform(.buildMap(operation, scene: snapshot.sceneName ?? "", name: name))
    }
    struct PendingTaskStart {
        let set: PredefinedSet
        fileprivate let sceneName: String
        fileprivate let connection: UUID
    }

    func prepareStart(of set: PredefinedSet) -> PendingTaskStart? {
        guard state == .ready, let scene, scene.name == snapshot.sceneName,
              scene.predefinedSets.contains(set), snapshot.allows(.startPredefined(set.id)) else { return nil }
        return PendingTaskStart(set: set, sceneName: scene.name, connection: connectionID)
    }

    func startPredefined(_ pending: PendingTaskStart) async {
        guard connectionID == pending.connection, snapshot.sceneName == pending.sceneName,
              scene?.name == pending.sceneName, scene?.predefinedSets.contains(pending.set) == true else { return }
        await perform(.startPredefined(pending.set.id))
    }

    struct PendingStationShortcut: Equatable {
        let shortcut: StationShortcut
        fileprivate let sceneName: String?
        fileprivate let mapID: String?
        fileprivate let connection: UUID

        fileprivate var command: RobotCommand {
            .stationShortcut(shortcut, scene: sceneName, mapID: mapID)
        }
    }

    func prepareShortcut(_ kind: Woosh_Task_Type, selected: String?) -> PendingStationShortcut? {
        guard foreground, state == .ready, let endpoint, reportedEndpoint == endpoint,
              snapshot.state == 2, snapshot.emergencyStopped == false, snapshot.charging == false else { return nil }
        let shortcut: StationShortcut?
        if let map = activeMap {
            shortcut = map.shortcut(for: kind, selected: selected, robotNumber: number)
        } else {
            shortcut = kind == .kCharge && selected == nil ? .charge(station: nil) : nil
        }
        guard let shortcut else { return nil }
        return PendingStationShortcut(shortcut: shortcut, sceneName: snapshot.sceneName,
                                     mapID: currentMapID, connection: connectionID)
    }

    func canSendShortcut(_ pending: PendingStationShortcut) -> Bool {
        let kind: Woosh_Task_Type
        switch pending.shortcut {
        case .charge: kind = .kCharge
        case .park: kind = .kParking
        }
        return prepareShortcut(kind, selected: pending.shortcut.station) == pending &&
            snapshot.allows(pending.command) && !pendingCommandTypes.contains(pending.command.type)
    }

    func sendShortcut(_ pending: PendingStationShortcut) async -> Result<Void, RobotRequestFailure>? {
        guard canSendShortcut(pending) else { return nil }
        return await request(pending.command)
    }
    func initializeInPlace() async { await initializePosition(.initializeInPlace) }

    func initializePosition(_ command: RobotCommand) async {
        let id = connectionID
        guard await perform(command) else { return }
        do {
            try await Task.sleep(for: .seconds(3))
            guard connectionID == id, state == .ready else { return }
            try await session.refreshScene()
        } catch { if connectionID == id { report(error) } }
    }

    func setInputBlocked(_ blocked: Bool, window: UUID) {
        if blocked { blockedWindows.insert(window); stopMotion() }
        else { blockedWindows.remove(window) }
    }

    private var motionGeneration = UUID()
    func move(_ velocity: RobotVelocity) {
        let ticket = UUID()
        motionGeneration = ticket
        Task {
            guard motionGeneration == ticket, canTeleoperate else { return }
            await session.teleoperate(velocity)
        }
    }
    func stopMotion() {
        motionGeneration = UUID()
        Task { await session.stopTeleoperation() }
    }

    func report(_ error: Error) {
        guard let failure = RobotRequestFailure(error) else { return }
        report(failure)
    }

    private func report(_ failure: RobotRequestFailure) {
        errorMessageIsLocal = failure.isLocal
        errorMessage = failure.message
    }
}
