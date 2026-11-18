import Foundation
import Observation
import WooshKit

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
                if previousScene != snapshot.sceneName, scene?.name != snapshot.sceneName {
                    scene = nil
                    sceneData = nil
                }
                if previousScene != snapshot.sceneName || previousMap != snapshot.mapID { loadCachedPreview() }
                if state == .ready, previousScene != snapshot.sceneName || previousMap != snapshot.mapID {
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
            await session.suspend()
        }
    }

    func updateTimeout() async {
        await session.setRequestTimeout(.seconds(max(1, settings.timeoutSeconds)))
    }

    @discardableResult
    func perform(_ command: RobotCommand) async -> Bool {
        guard foreground, state == .ready, reportedEndpoint == endpoint, snapshot.allows(command),
              pendingCommandTypes.insert(command.type).inserted else { return false }
        let id = connectionID
        defer { if id == connectionID { pendingCommandTypes.remove(command.type) } }
        do {
            try await session.perform(command)
            return connectionID == id
        } catch {
            if connectionID == id { report(error) }
            return false
        }
    }

    func controlTask(_ command: TaskControl) async { await perform(.taskControl(command)) }
    func switchWorkMode(_ mode: Int) async { await perform(.workMode(mode)) }
    func buildMap(_ operation: MapBuildOperation, name: String) async {
        await perform(.buildMap(operation, scene: snapshot.sceneName ?? "", name: name))
    }
    func startPredefined(_ id: Int) async {
        guard scene?.predefinedSets.contains(where: { $0.id == id }) == true else { return }
        await perform(.startPredefined(id))
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
        if error is CancellationError { return }
        errorMessageIsLocal = true
        if case SessionError.rejected(let message) = error, !message.isEmpty { errorMessageIsLocal = false; errorMessage = message }
        else if error as? TransportError == .timeout { errorMessage = "요청 시간이 초과되었습니다." }
        else { errorMessage = "요청에 실패했습니다. 로봇 연결을 확인하세요." }
    }
}
