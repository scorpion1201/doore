import SwiftUI
import WooshKit

enum DesignTab: String, CaseIterable {
    case monitor = "모니터", deploy = "배치", statistics = "통계"

    var symbol: String {
        switch self {
        case .monitor: "point.3.connected.trianglepath.dotted"
        case .deploy: "pencil.and.outline"
        case .statistics: "chart.bar.xaxis"
        }
    }
}

private struct UndoDraftKey: FocusedValueKey { typealias Value = () -> Void }
private struct RedoDraftKey: FocusedValueKey { typealias Value = () -> Void }
private struct SaveDraftKey: FocusedValueKey { typealias Value = () -> Void }
private struct DesignLayersKey: FocusedValueKey { typealias Value = Binding<Set<String>> }

extension FocusedValues {
    var designUndo: (() -> Void)? {
        get { self[UndoDraftKey.self] }
        set { self[UndoDraftKey.self] = newValue }
    }
    var designRedo: (() -> Void)? {
        get { self[RedoDraftKey.self] }
        set { self[RedoDraftKey.self] = newValue }
    }
    var designSave: (() -> Void)? {
        get { self[SaveDraftKey.self] }
        set { self[SaveDraftKey.self] = newValue }
    }
    var designLayers: Binding<Set<String>>? {
        get { self[DesignLayersKey.self] }
        set { self[DesignLayersKey.self] = newValue }
    }
}

struct DesignScreen: View {
    @Environment(\.compactLayout) private var compact
    @State private var tab: DesignTab
    @AppStorage("designVisibleLayers") private var storedLayers = DesignLayerButtons.names.joined(separator: "|")

    init(initialTab: DesignTab = .monitor) {
        _tab = State(initialValue: initialTab)
    }

    private var layers: Binding<Set<String>> {
        Binding(get: { Set(storedLayers.split(separator: "|").map(String.init)) },
                set: { storedLayers = $0.sorted().joined(separator: "|") })
    }

    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(spacing: DooreSize.compactGap))
                             : AnyLayout(HStackLayout(spacing: DooreSize.gap))
        layout {
            rail
            switch tab {
            case .monitor: DesignMonitor(layers: layers)
            case .deploy: DesignDeploy(layers: layers)
            case .statistics: DesignStatistics()
            }
        }
        #if os(macOS)
        .focusedSceneValue(\.designLayers, tab == .statistics ? nil : layers)
        #endif
    }

    private var rail: some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: DooreSize.tightGap))
                             : AnyLayout(VStackLayout(spacing: DooreSize.smallGap))
        return layout {
            ForEach(DesignTab.allCases, id: \.self) { choice in
                Button {
                    tab = choice
                } label: {
                    VStack(spacing: DooreSize.tightGap) {
                        Image(systemName: choice.symbol)
                            .font(.system(size: compact ? DooreSize.statusIcon : DooreSize.railIcon))
                        Text(choice == .monitor ? LocalizedStringKey("design.monitor") : LocalizedStringKey(choice.rawValue))
                    }
                    .frame(maxWidth: .infinity, minHeight: compact ? DooreSize.buttonHeight : DooreSize.railItemHeight)
                    .foregroundStyle(tab == choice ? DooreColor.ink : DooreColor.inkSoft)
                    .background(tab == choice ? DooreColor.surface : DooreColor.tab,
                                in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == choice ? .isSelected : [])
            }
            if !compact { Spacer(minLength: 0) }
        }
        .frame(width: compact ? nil : DooreSize.designRail)
    }
}

struct DesignIconButton: View {
    let title: String
    let icon: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(minWidth: DooreSize.smallButtonHeight, minHeight: DooreSize.smallButtonHeight)
                .foregroundStyle(selected ? DooreColor.primary : DooreColor.ink)
                .overlay(RoundedRectangle(cornerRadius: DooreSize.fieldRadius)
                    .strokeBorder(selected ? DooreColor.primary : DooreColor.line, lineWidth: DooreSize.hairline))
                .frame(minWidth: DooreSize.tapTarget, minHeight: DooreSize.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(Text(LocalizedStringKey(title)))
    }
}

struct DesignLayerButtons: View {
    static let names = ["자", "주행 금지", "교통 통제", "구역", "스테이션", "경로", "로봇"]
    static let symbols = ["ruler", "square.3.layers.3d", "map", "scope", "mappin.circle", "line.diagonal", "car"]
    @Binding var layers: Set<String>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.names.indices, id: \.self) { index in
                let key = Self.names[index]
                DesignIconButton(title: key, icon: Self.symbols[index], selected: layers.contains(key)) {
                    if layers.contains(key) { layers.remove(key) } else { layers.insert(key) }
                }
            }
        }
    }
}

struct DesignMonitor: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @Binding var layers: Set<String>
    @State private var station: String?
    @State private var follow = false
    @State private var inspected: MapPose?
    @State private var dialog: String?

    var body: some View {
        Group {
            if compact {
                ScrollView {
                    VStack(spacing: DooreSize.compactGap) {
                        robotList
                        mapPanel
                    }
                }
            } else {
                HStack(spacing: DooreSize.gap) {
                    robotList.frame(width: DooreSize.designRobotList)
                    mapPanel
                }
            }
        }
        .sheet(isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })) {
            VStack(spacing: DooreSize.gap) {
                Text(LocalizedStringKey(dialog ?? "")).font(.headline)
                if dialog == "로봇 정보" {
                    Grid(alignment: .leading) {
                        row("정보", robot.name)
                        row("구성", robot.number)
                        row("모드", robot.workModeLabel, localized: true)
                        row("상태", robot.stateLabel, localized: true)
                        row("장면", robot.scene?.name)
                    }
                } else if dialog == "사전 정의 작업" {
                    let sets = robot.scene?.predefinedSets ?? []
                    if sets.isEmpty { Text("사전 정의 작업이 없습니다.") }
                    else {
                        ScrollView {
                            ForEach(sets) { set in
                                LabeledContent { Text("작업 \(set.taskCount)개") } label: { Text(verbatim: set.name) }
                            }
                        }
                    }
                } else if dialog == "충전 설정" {
                    let limits = [("경고", "alarm"), ("저전력", "low"), ("대기", "idle"), ("작업", "work"), ("만충전", "full")]
                    Grid(alignment: .leading) {
                        ForEach(limits.indices, id: \.self) { i in
                            row(LocalizedStringKey(limits[i].0), robot.snapshot.thresholds[limits[i].1].map { "\($0)%" })
                        }
                    }
                }
                Button("닫기") { dialog = nil }.buttonStyle(DooreButtonStyle(.primary))
            }.padding(DooreSize.dialogPadding)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String?, localized: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(DooreColor.inkSoft)
            if localized { Text(LocalizedStringKey(value ?? "—")) }
            else { Text(verbatim: value ?? "—") }
        }
    }

    private var robotList: some View {
        VStack(alignment: .leading, spacing: DooreSize.smallGap) {
            HStack {
                Text("로봇 목록").font(.headline)
                if robot.state == .ready { Text("1대") }
                Spacer()
            }
            if robot.state == .ready {
                VStack(alignment: .leading, spacing: DooreSize.smallGap) {
                    Button {
                        station = nil
                        follow = true
                    } label: {
                        VStack(alignment: .leading, spacing: DooreSize.tightGap) {
                            if let number = robot.number { Text(verbatim: "No. " + number) }
                            Text(verbatim: robot.name ?? robot.host ?? "—").font(.headline)
                            if let state = robot.stateLabel { Text(LocalizedStringKey(state)) }
                            if let host = robot.host { Text(verbatim: host) }
                            if let power = robot.battery { Label("\(power)%", systemImage: "battery.100percent") }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button("상세") { dialog = "로봇 정보" }.buttonStyle(DooreButtonStyle(.line, small: true))
                }.padding(DooreSize.compactPanelPadding)
                    .background(follow ? DooreColor.primaryTint : DooreColor.well,
                                in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                Spacer(minLength: 0)
            } else {
                RobotRegionState(message: "로봇에 연결하면 로봇 목록이 여기에 표시됩니다.")
            }
            HStack {
                Button("충전 설정") { dialog = "충전 설정" }.disabled(compact || robot.state != .ready)
                Button("사전 정의 작업") { dialog = "사전 정의 작업" }.disabled(robot.state != .ready)
            }.buttonStyle(DooreButtonStyle(.primary, square: true, fullWidth: true))
        }.doorePanel()
    }

    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: DooreSize.smallGap) {
            ScrollView(.horizontal) {
                HStack {
                    Text("장면"); Text(verbatim: robot.scene?.name ?? "—")
                    Text("지도"); Text(verbatim: robot.activeMap?.name ?? "—")
                    Text("ID"); Text(verbatim: robot.activeMap?.id ?? "—")
                    Text("층"); Text(verbatim: robot.activeMap?.floor ?? "—")
                    Button("내비게이션") {}.buttonStyle(DooreButtonStyle(.line, small: true)).disabled(true)
                    if let inspected { Text(verbatim: String(format: "(%.2f, %.2f)", inspected.x, inspected.y)) }
                }.monospacedDigit()
            }
            MapCanvasView(map: robot.activeMap, pose: robot.poseMapID == robot.activeMap?.id ? robot.pose : nil,
                          selected: $station, followsRobot: $follow, layers: layers, onInspect: { inspected = $0 })
                .frame(minHeight: compact ? DooreSize.compactMapHeight : nil)
            Text("목록에서 로봇을 고르면 지도가 그 로봇으로 이동합니다.").foregroundStyle(DooreColor.inkSoft)
            ScrollView(.horizontal) { DesignLayerButtons(layers: $layers) }
        }.doorePanel()
    }
}
