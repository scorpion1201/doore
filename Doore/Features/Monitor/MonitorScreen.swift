import SwiftUI
import WooshKit

struct MonitorScreen: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var showTasks = false
    @State private var dispatch = false
    @State private var selected: String?
    @State private var follow = false
    @State private var confirmation: TaskControl?
    @State private var showRequest = false
    @State private var selectedSet: Int?
    @State private var starting: PredefinedSet?
    @State private var copying: PredefinedSet?

    private var map: MapModel? { robot.activeMap }
    private var running: Bool { robot.state == .ready && robot.taskStateLabel == "실행 중" }
    private var paused: Bool { robot.state == .ready && robot.taskStateLabel == "일시정지" }

    var body: some View {
        VStack(spacing: DooreSize.smallGap) {
            if compact {
                Picker("모니터", selection: $showTasks) {
                    Text("지도").tag(false); Text("작업 목록").tag(true)
                }.pickerStyle(.segmented)
                if showTasks { list.doorePanel() } else { mapPanel.doorePanel() }
                taskControls
                quickActions
            } else {
                HStack(spacing: DooreSize.gap) {
                    list.doorePanel().frame(width: DooreSize.sidePanel)
                    mapPanel.doorePanel()
                }
                HStack { taskControls; Spacer(); quickActions }
            }
            if robot.state == .ready {
                Text("충전·주차 바로가기와 작업 건너뛰기는 로봇 모델별 명령을 확인해야 합니다.")
                    .foregroundStyle(DooreColor.inkSoft)
            }
        }
        .onChange(of: map?.id) { _, _ in selected = nil }
        .onChange(of: selected) { _, number in if number != nil { follow = false } }
        .focusedSceneValue(\.taskPause, running ? { confirmation = .pause } : nil)
        .focusedSceneValue(\.taskResume, paused ? { confirmation = .resume } : nil)
        .focusedSceneValue(\.taskCancel, (running || paused) ? { confirmation = .cancel } : nil)
        .alert(question, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { command in
            Button("취소", role: .cancel) {}
            Button("확인") { Task { await robot.controlTask(command) } }
        }
        .alert("선택한 작업 묶음을 실행할까요?", isPresented: Binding(get: { starting != nil }, set: { if !$0 { starting = nil } }), presenting: starting) { set in
            Button("취소", role: .cancel) {}
            Button("확인") { Task { await robot.startPredefined(set.id) } }
        } message: { set in Text(verbatim: set.name) }
        .sheet(item: $copying) { set in
            VStack(alignment: .trailing) {
                Button("닫기") { copying = nil }.buttonStyle(DooreButtonStyle(.quiet))
                TaskScreen(source: set)
            }.padding(DooreSize.panelPadding)
        }
        .sheet(isPresented: $showRequest) {
            StationTaskForm(station: selected, isDraft: false, onSave: nil)
        }
    }

    private var question: LocalizedStringKey {
        switch confirmation {
        case .pause: return "작업을 일시정지할까요?"
        case .resume: return "작업을 계속할까요?"
        case .cancel: return "작업을 취소할까요?"
        case nil: return ""
        }
    }

    private var list: some View {
        VStack {
            Picker("작업 목록", selection: $dispatch) {
                Text("사전 정의 작업").tag(false)
                Text("관제 작업").tag(true)
            }.pickerStyle(.segmented)
            if !dispatch, let sets = robot.scene?.predefinedSets, !sets.isEmpty {
                ScrollView {
                    VStack {
                        ForEach(sets) { set in
                            Button { selectedSet = set.id } label: {
                                HStack {
                                    Text(verbatim: set.name)
                                    Spacer()
                                    Text("작업 \(set.taskCount)개")
                                    if selectedSet == set.id { Image(systemName: "checkmark") }
                                }.padding(DooreSize.compactPanelPadding).background(DooreColor.well, in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                            }.buttonStyle(.plain)
                                .contextMenu {
                                    Button("작업 편집") { copying = set }
                                }
                        }
                    }
                }
            } else {
                RobotRegionState(message: "로봇에 연결하면 작업 목록이 여기에 표시됩니다.",
                             empty: dispatch ? "관제 작업 목록을 받지 못했습니다." : "표시할 사전 정의 작업이 없습니다.")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapPanel: some View {
        VStack(spacing: DooreSize.smallGap) {
            OperateMapHeader(map: map, follow: $follow)
            MapCanvasView(map: map ?? robot.syncingMapPreview, pose: robot.poseMapID == map?.id ? robot.pose : nil,
                          selected: robot.state == .ready ? $selected : .constant(nil), followsRobot: follow)
                .allowsHitTesting(map != nil || robot.syncingMapPreview == nil)
            if let stations = map?.stations, !stations.isEmpty {
                ScrollViewReader { proxy in
                    HStack {
                        Button { page(stations, by: -1, proxy) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("이전 스테이션")
                        ScrollView(.horizontal) {
                            HStack(spacing: DooreSize.smallGap) {
                                ForEach(stations, id: \.number) { station in
                                    Button {
                                        selected = station.number
                                    } label: {
                                        Text(verbatim: station.number)
                                            .fontWeight(selected == station.number ? .semibold : .regular)
                                            .padding(.horizontal, DooreSize.compactGap)
                                            .frame(minHeight: DooreSize.buttonHeight)
                                            .background(selected == station.number ? DooreColor.primaryTint : DooreColor.surface, in: Capsule())
                                            .overlay { Capsule().strokeBorder(DooreColor.primary, lineWidth: DooreSize.outline) }
                                    }.buttonStyle(.plain).id(station.number)
                                }
                            }
                        }
                        Button { page(stations, by: 1, proxy) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("다음 스테이션")
                    }
                }
            }
        }
    }

    private func page(_ stations: [Station], by step: Int, _ proxy: ScrollViewProxy) {
        let index = stations.firstIndex { $0.number == selected } ?? (step > 0 ? -1 : stations.count)
        let next = stations[min(stations.count - 1, max(0, index + step))].number
        selected = next
        withAnimation { proxy.scrollTo(next, anchor: .center) }
    }

    private var taskControls: some View {
        HStack {
            if running || paused {
                Button(paused ? LocalizedStringKey("계속") : LocalizedStringKey("일시정지")) {
                    confirmation = paused ? .resume : .pause
                }.buttonStyle(DooreButtonStyle(.line))
                Button("취소") { confirmation = .cancel }.buttonStyle(DooreButtonStyle(.line))
                Button("건너뛰기") {}.buttonStyle(DooreButtonStyle(.line)).disabled(true)
            } else {
                Button("시작") { starting = robot.scene?.predefinedSets.first { $0.id == selectedSet } }
                    .buttonStyle(DooreButtonStyle(.line))
                    .disabled(dispatch || selectedSet == nil || robot.state != .ready || robot.snapshot.controlMode != 1 || robot.snapshot.workMode != 2 || robot.snapshot.state != 2)
            }
        }
    }

    private var quickActions: some View {
        HStack {
            if selected != nil {
                Button("작업") { showRequest = true }.buttonStyle(DooreButtonStyle(.primary))
            }
            Button("충전") {}.buttonStyle(DooreButtonStyle(.primary)).disabled(true)
            Button("주차") {}.buttonStyle(DooreButtonStyle(.quiet)).disabled(true)
        }
    }
}
