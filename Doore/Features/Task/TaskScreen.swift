import SwiftUI
import WooshKit

struct TaskScreen: View {
    @State private var draft: TaskStore

    init(source: PredefinedSet? = nil) { _draft = State(initialValue: TaskStore(source: source)) }
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var station: String?
    @State private var mapID: String?
    @State private var follow = false
    @State private var editing: TaskDraftItem?
    @State private var deleting = false
    @State private var showMap = false
    @State private var destination: TaskSubmission.Destination?
    private var map: MapModel? { robot.scene?.map(id: mapID) ?? robot.activeMap }

    var body: some View {
        Group {
            if compact && !showMap { detail }
            else if compact {
                VStack(alignment: .leading) {
                    Button("작업 묶음 구성") { showMap = false }.buttonStyle(DooreButtonStyle(.line))
                    mapPanel
                }
            } else {
                HStack(spacing: DooreSize.gap) {
                    mapPanel
                    detail.frame(width: DooreSize.sidePanel)
                }
            }
        }
        .sheet(item: $editing) { item in
            StationTaskForm(station: item.station, isDraft: true, initial: item) { changed in
                draft.save(changed)
                showMap = false
            }
        }
        .alert("선택한 작업을 삭제할까요?", isPresented: $deleting) {
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) { draft.deleteSelection() }
        }
        .alert(destination == .predefined ? LocalizedStringKey("사전 정의 작업으로 저장할까요?") : LocalizedStringKey("작업 묶음을 보낼까요?"),
               isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } }), presenting: destination) { choice in
            Button("취소", role: .cancel) {}
            Button("확인") {
                guard let command = draft.submission(choice, scene: robot.scene, map: map) else { return }
                Task { _ = await robot.perform(.taskSubmission(command)) }
            }
        }
        .onChange(of: robot.scene?.name) { _, _ in clearDraft() }
        .onChange(of: mapID) { _, _ in station = nil }
    }

    private var mapPanel: some View {
        VStack(alignment: .leading) {
            OperateMapHeader(map: map, follow: $follow)
            MapCanvasView(map: map, pose: robot.poseMapID == map?.id ? robot.pose : nil, selected: $station, followsRobot: follow)
            MapCards(scene: robot.scene, map: map, select: { mapID = $0.id })
            if compact, let station {
                Button("작업 추가") { editing = TaskDraftItem(station: station) }.buttonStyle(DooreButtonStyle(.primary))
            }
        }.doorePanel()
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: DooreSize.smallGap) {
            Text("작업 묶음 구성").font(.headline).frame(maxWidth: .infinity)
            LabeledContent("이름") { TextField("임시 작업", text: $draft.name).dooreField() }
            if let source = draft.source {
                LabeledContent("사전 정의 작업", value: source.name)
                Text("다른 이름으로 저장하면 새 작업 묶음이 만들어집니다.").foregroundStyle(DooreColor.inkSoft)
            }
            LabeledContent("반복 횟수") { TextField("반복 횟수", text: $draft.repeats).dooreField() }
            Text("-1은 무한 반복, 0은 한 번 실행").foregroundStyle(DooreColor.inkSoft)
            if compact {
                Button("지도") { showMap = true }.buttonStyle(DooreButtonStyle(.line))
            }
            if draft.items.isEmpty {
                RobotRegionState(message: "로봇에 연결하면 목표 스테이션을 선택할 수 있습니다.", empty: "지도에서 스테이션을 선택하세요.")
            } else {
                List {
                    ForEach(draft.items) { item in
                        Button { draft.selectedID = item.id } label: {
                            HStack {
                                if draft.selectedID == item.id { Image(systemName: "checkmark") }
                                Text(verbatim: item.station)
                                Text(LocalizedStringKey(item.kind)); Text(LocalizedStringKey(item.direction))
                                Text("대기 \(item.wait)초")
                            }
                        }.buttonStyle(.plain)
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { dropped, _ in
                                guard let id = dropped.first.flatMap(UUID.init(uuidString:)) else { return false }
                                return draft.move(id, to: item.id)
                            }
                    }.onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                }.listStyle(.plain)
            }
            HStack {
                Button("작업 추가") { if let station { editing = TaskDraftItem(station: station) } }
                    .buttonStyle(DooreButtonStyle(.primary, small: true)).disabled(station == nil)
                Button("작업 편집") { editing = draft.selectedItem }
                    .buttonStyle(DooreButtonStyle(.primary, small: true)).disabled(draft.selectedItem == nil)
                Button("작업 삭제") { deleting = true }
                    .buttonStyle(DooreButtonStyle(.danger, small: true)).disabled(draft.selectedItem == nil)
            }
            Text("목록을 길게 눌러 끌면 순서가 바뀝니다.").foregroundStyle(DooreColor.inkSoft)
            if !draft.items.isEmpty && draft.items.contains(where: { $0.group == nil }) { Text("동작 조합을 확인한 뒤 보낼 수 있습니다.").foregroundStyle(DooreColor.inkSoft) }
            HStack {
                Button("사전 정의로 저장") { destination = .predefined }.buttonStyle(DooreButtonStyle(.line)).disabled(!canSubmit(.predefined))
                Button("작업 묶음 보내기") { destination = .taskSet }.buttonStyle(DooreButtonStyle(.line)).disabled(!canSubmit(.taskSet))
            }
            if let value = Int(draft.repeats), value != 0 { Text("반복 작업은 사전 정의로 저장한 뒤 모니터에서 시작하세요.").foregroundStyle(DooreColor.inkSoft) }
        }.doorePanel()
    }

    private func canSubmit(_ destination: TaskSubmission.Destination) -> Bool {
        robot.state == .ready && draft.submission(destination, scene: robot.scene, map: map)?.allows(robot.snapshot) == true
    }

    private func clearDraft() {
        draft = TaskStore(); station = nil; mapID = nil; editing = nil
    }
}

struct StationTaskForm: View {
    let station: String?
    let isDraft: Bool
    var initial: TaskDraftItem?
    let onSave: ((TaskDraftItem) -> Void)?
    @Environment(RobotStore.self) private var robot
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "픽"
    @State private var direction = "적재"
    @State private var wait = "0"
    @State private var custom = ""
    @State private var group: Int32?
    private var kindCode: Int { ["픽": 1, "주차": 2, "충전": 3, "운반": 4][kind] ?? 0 }
    private var groups: [Int32] { robot.scene?.referencedGroups[kindCode]?.sorted() ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DooreSize.smallGap) {
                Text(isDraft ? LocalizedStringKey("작업 편집") : LocalizedStringKey("작업")).font(.title2)
                if !isDraft { ModeBanner(requiredWork: "작업", mode: 2) }
                Picker("종류", selection: $kind) {
                    ForEach(["픽", "주차", "충전", "운반"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                }
                Picker("방향", selection: $direction) {
                    if direction == "—" { Text(verbatim: "—").tag("—") }
                    Text("적재").tag("적재"); Text("하역").tag("하역")
                }
                if groups.isEmpty {
                    LabeledContent("동작 조합", value: "—")
                    Text("동작 조합을 확인한 뒤 보낼 수 있습니다.").foregroundStyle(DooreColor.inkSoft)
                } else {
                    Picker("동작 조합", selection: $group) {
                        Text("선택").tag(Optional<Int32>.none)
                        ForEach(groups, id: \.self) { number in Text(verbatim: String(number)).tag(Optional(number)) }
                    }
                    Text("현재 장면의 사전 정의 작업에서 사용 중인 조합 번호입니다.").foregroundStyle(DooreColor.inkSoft)
                }
                LabeledContent("목적지", value: station ?? "—")
                if let p = robot.activeMap?.stations.first(where: { $0.number == station })?.pose {
                    LabeledContent("위치", value: String(format: "(%.2f, %.2f)", p.x, p.y))
                }
                TextField("사용자 정의", text: $custom).dooreField()
                if isDraft {
                    TextField("대기 시간", text: $wait).dooreField()
                    Text("-1은 계속 대기, 0은 대기 없음").foregroundStyle(DooreColor.inkSoft)
                }
                HStack {
                    Button("닫기") { dismiss() }.buttonStyle(DooreButtonStyle(.quiet))
                    if isDraft {
                        Button("확인") {
                            guard let station, let seconds = Int(wait), seconds >= -1 else { return }
                            var item = initial ?? TaskDraftItem(station: station)
                            item.kind = kind; item.direction = direction; item.group = group; item.wait = seconds; item.custom = custom
                            onSave?(item); dismiss()
                        }.buttonStyle(DooreButtonStyle(.primary)).disabled(Int(wait).map { $0 < -1 } ?? true)
                    } else {
                        Button("보내기") {
                            guard let command = single else { return }
                            Task { if await robot.perform(.taskSubmission(command)) { dismiss() } }
                        }.buttonStyle(DooreButtonStyle(.primary)).disabled(robot.state != .ready || single?.allows(robot.snapshot) != true)
                    }
                }
            }.padding(DooreSize.dialogPadding)
        }.onChange(of: kind) { _, _ in if let group, !groups.contains(group) { self.group = nil } }
        .onAppear {
            if let initial {
                kind = initial.kind; direction = initial.direction
                wait = String(initial.wait); custom = initial.custom; group = initial.group
            }
        }
    }

    private var single: TaskSubmission? {
        guard let station, let group, let map = robot.activeMap, let scene = robot.scene else { return nil }
        let task = StationTask(station: station, kind: kindCode, direction: direction == "적재" ? 1 : 2, group: group, wait: 0, custom: custom)
        return TaskSubmission(scene: scene, mapID: map.id, tasks: [task], destination: .single)
    }
}
