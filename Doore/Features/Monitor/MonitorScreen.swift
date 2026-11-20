import SwiftUI
import WooshKit

struct MonitorScreen: View {
    let confirmShortcut: (RobotStore.PendingStationShortcut) -> Void
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var showTasks = false
    @State private var dispatch = false
    @State private var selected: String?
    @State private var follow = false
    @State private var stationFocusRequest = 0
    @State private var confirmation: RobotStore.PendingTaskControl?
    @State private var showRequest = false
    @State private var selectedSet: Int?
    @State private var starting: RobotStore.PendingTaskStart?
    @State private var copying: PredefinedSet?

    private var map: MapModel? { robot.activeMap }
    private var running: Bool { robot.state == .ready && robot.taskStateLabel == "실행 중" }
    private var paused: Bool { robot.state == .ready && robot.taskStateLabel == "일시정지" }
    private var chosenSet: PredefinedSet? { robot.scene?.predefinedSets.first { $0.id == selectedSet } }

    private var workspace: some View {
        Group {
            if compact {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: DooreSize.smallGap) {
                            Picker("모니터", selection: $showTasks) {
                                Text("지도").tag(false); Text("작업 목록").tag(true)
                            }.pickerStyle(.segmented)
                            if showTasks { list } else { mapPanel.doorePanel() }
                            taskControls
                            quickActions
                        }.frame(minHeight: geometry.size.height)
                    }.scrollBounceBehavior(.basedOnSize)
                }
            } else {
                VStack(spacing: DooreSize.gap) {
                    HStack(spacing: DooreSize.gap) {
                        list.frame(width: DooreSize.sidePanel)
                        mapPanel.doorePanel()
                    }
                    HStack(alignment: .bottom) { taskControls; Spacer(); quickActions }
                }
            }
        }
        .onChange(of: robot.scene?.name) { _, _ in selected = nil; selectedSet = nil; starting = nil }
        .onChange(of: chosenSet) { _, set in
            if starting?.set != set { starting = nil }
        }
        .onChange(of: map?.id) { _, _ in selected = nil }
        .onChange(of: map?.stations) { _, stations in
            if let selected, stations?.contains(where: { $0.number == selected }) != true { self.selected = nil }
        }
    }

    private var currentControl: RobotStore.PendingTaskControl? {
        confirmation.flatMap { robot.prepareControl($0.control) }
    }

    var body: some View {
        workspace
        .onChange(of: currentControl) { _, current in
            if current != confirmation { confirmation = nil }
        }
        .focusedSceneValue(\.taskPause, confirmControl(.pause))
        .focusedSceneValue(\.taskResume, confirmControl(.resume))
        .focusedSceneValue(\.taskCancel, confirmControl(.cancel))
        .alert(question, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { command in
            Button("취소", role: .cancel) {}
            Button("확인") { Task { await robot.controlTask(command) } }
        }
        .alert("선택한 작업 묶음을 실행할까요?", isPresented: Binding(get: { starting != nil }, set: { if !$0 { starting = nil } }), presenting: starting) { pending in
            Button("취소", role: .cancel) {}
            Button("확인") { Task { await robot.startPredefined(pending) } }
        } message: { pending in Text(verbatim: pending.set.name) }
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
        switch confirmation?.control {
        case .pause: return "작업을 일시정지할까요?"
        case .resume: return "작업을 계속할까요?"
        case .cancel: return "작업을 취소할까요?"
        case .breakWait: return "건너뛰기"
        case nil: return ""
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                listTab("사전 정의 작업", dispatchTab: false)
                listTab("관제 작업", dispatchTab: true)
            }
            if !dispatch, chosenSet != nil {
                ModeBanner(requiredWork: "작업", mode: 2)
            }
            if !dispatch, let sets = robot.scene?.predefinedSets, !sets.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DooreSize.smallGap) {
                        ForEach(sets) { set in
                            Button { selectedSet = set.id } label: {
                                HStack(spacing: DooreSize.compactGap) {
                                    Text(verbatim: set.name)
                                        .fontWeight(selectedSet == set.id ? .semibold : .regular)
                                    Text("작업 \(set.taskCount)개")
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, DooreSize.compactGap)
                                .padding(.vertical, DooreSize.compactPanelPadding)
                                .background(DooreColor.well, in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                                .overlay {
                                    if selectedSet == set.id {
                                        RoundedRectangle(cornerRadius: DooreSize.rowRadius)
                                            .strokeBorder(DooreColor.primary, lineWidth: DooreSize.outline)
                                    }
                                }
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(selectedSet == set.id ? .isSelected : [])
                                .contextMenu {
                                    Button("작업 편집") { copying = set }
                                }
                        }
                    }.padding(compact ? DooreSize.compactPanelPadding : DooreSize.panelPadding)
                }.frame(minHeight: DooreSize.mapMinimum)
            } else {
                RobotRegionState(message: "로봇에 연결하면 작업 목록이 여기에 표시됩니다.",
                             empty: dispatch ? "관제 작업 목록을 받지 못했습니다." : "표시할 사전 정의 작업이 없습니다.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DooreColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DooreSize.radius))
    }

    private func listTab(_ title: LocalizedStringKey, dispatchTab: Bool) -> some View {
        let active = dispatch == dispatchTab
        return Button { dispatch = dispatchTab } label: {
            Text(title)
                .dooreFont(compact ? DooreSize.smallFont : DooreSize.monitorTabFont, weight: active ? .semibold : .regular)
                .padding(.vertical, DooreSize.smallGap)
                .frame(maxWidth: .infinity, minHeight: DooreSize.tapTarget)
                .background(active ? DooreColor.surface : DooreColor.tab)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var mapPanel: some View {
        VStack(spacing: DooreSize.smallGap) {
            OperateMapHeader(map: map, follow: $follow)
            MapCanvasView(map: map ?? robot.syncingMapPreview, pose: robot.poseMapID == map?.id ? robot.pose : nil,
                          selected: robot.state == .ready ? $selected : .constant(nil), followsRobot: $follow,
                          stationFocusRequest: stationFocusRequest)
                .allowsHitTesting(map != nil || robot.syncingMapPreview == nil)
            if let stations = map?.stations, !stations.isEmpty {
                MonitorStationStrip(stations: stations, selected: selected) { number in
                    selected = number
                    follow = false
                    stationFocusRequest += 1
                }
            }
        }
    }

    private var taskControls: some View {
        HStack(spacing: DooreSize.smallGap) {
            if running || paused || robot.snapshot.taskIsWaiting {
                controlButton(paused ? "계속" : "일시정지", paused ? .resume : .pause)
                controlButton("취소", .cancel)
                controlButton("건너뛰기", .breakWait)
            } else {
                let pending = chosenSet.flatMap(robot.prepareStart(of:))
                Button("시작") { starting = pending }.disabled(dispatch || pending == nil)
            }
        }.buttonStyle(DooreButtonStyle(.line, fullWidth: compact))
    }

    private func confirmControl(_ control: TaskControl) -> (() -> Void)? {
        guard let pending = robot.prepareControl(control) else { return nil }
        return { confirmation = pending }
    }

    private func controlButton(_ label: LocalizedStringKey, _ control: TaskControl) -> some View {
        let confirm = confirmControl(control)
        return Button(label) { confirm?() }.disabled(confirm == nil)
    }

    private var quickActions: some View {
        HStack(spacing: DooreSize.smallGap) {
            if selected != nil {
                quickAction("작업") { showRequest = true }
            }
            let charge = robot.prepareShortcut(.kCharge, selected: selected)
            quickAction("충전") { if let charge { confirmShortcut(charge) } }
                .disabled(charge == nil)
            let park = robot.prepareShortcut(.kParking, selected: selected)
            quickAction("주차", quiet: true) { if let park { confirmShortcut(park) } }
                .disabled(park == nil)
                .accessibilityHint("지도에서 스테이션을 선택하세요.")
        }
    }

    private func quickAction(_ title: LocalizedStringKey, quiet: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).dooreFont(compact ? DooreSize.smallFont : DooreSize.buttonFont)
                .frame(maxWidth: compact ? .infinity : DooreSize.quickAction,
                       minHeight: compact ? DooreSize.buttonHeight : DooreSize.quickAction)
                .foregroundStyle(quiet ? DooreColor.ink : DooreColor.primaryInk)
                .background(quiet ? DooreColor.quiet : DooreColor.primary,
                            in: RoundedRectangle(cornerRadius: DooreSize.radius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dooreHover()
    }
}
