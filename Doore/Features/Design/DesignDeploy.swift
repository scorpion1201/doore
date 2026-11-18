import SwiftUI
import WooshKit
#if os(iOS)
import UIKit
#endif

private enum PaletteGroup: String, CaseIterable {
    case base = "바탕 지도", field = "구역", guide = "소프트 가이드", point = "포인트"

    var subtypes: [String] {
        switch self {
        case .base: ["통행 가능", "미탐색", "벽", "주행 금지", "교통 통제"]
        case .field: ["양방향", "단일 차로", "일방통행", "교차로", "협로", "위치 보정", "경사", "주행거리계", "자동문", "속도 제한", "소방", "경고", "유도"]
        case .guide: ["단방향 경로", "양방향 경로"]
        case .point: ["스테이션", "선반", "주차 자리", "충전기", "팔레트 대", "리프트 카트", "견인 트레일러", "롤러 스테이션", "로봇 팔 작업대", "웜홀", "유도점", "QR 코드"]
        }
    }
}

struct DesignDeploy: View {
    @Environment(RobotStore.self) private var robot
    @Environment(SceneEditingWorkspace.self) private var workspace
    @Environment(\.compactLayout) private var compact
    @Binding var layers: Set<String>
    @State private var tool: PaletteGroup?
    @State private var choices: [PaletteGroup: String] = [:]
    @State private var brush = "선"
    @State private var start: MapPose?
    @State private var pointer: MapPose?
    @State private var selectedStation: String?
    @State private var libraryPresented = false
    @State private var saving = false
    @State private var editingTasks = false
    @State private var showingActions = false
    @State private var deleteItem = false
    @State private var edgeSnap = false

    private var readOnly: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone || compact
        #else
        return compact
        #endif
    }
    private var selected: DraftItem? { workspace.draft.items.first { $0.id == workspace.selection } }
    private var editEnabled: Bool { !readOnly && workspace.map != nil && !workspace.busy }
    private func subtype(_ key: PaletteGroup) -> String { choices[key] ?? key.subtypes[0] }

    var body: some View {
        Group {
            if compact {
                ScrollView {
                    VStack(spacing: DooreSize.compactGap) {
                        canvas.frame(minHeight: DooreSize.compactMapHeight)
                        if selected != nil { properties }
                        libraryButton
                    }
                }
            } else {
                HStack(spacing: DooreSize.compactGap) {
                    palette.frame(width: DooreSize.designPalette)
                    canvas
                    properties.frame(width: DooreSize.designInspector)
                }
            }
        }
        .onChange(of: robot.activeMap?.id, initial: true) { _, _ in openFirstSource() }
        .onChange(of: robot.state) { _, next in if next == .ready { openFirstSource() } }
        .onChange(of: workspace.source?.id) { _, _ in
            start = nil
            pointer = nil
            selectedStation = nil
        }
        .sheet(isPresented: $libraryPresented) { DesignSceneLibrary().environment(workspace) }
        .sheet(isPresented: $editingTasks) { DesignTaskSets().environment(workspace) }
        .sheet(isPresented: $showingActions) {
            VStack(spacing: DooreSize.gap) {
                Text("동작 조합").font(.headline)
                if workspace.actionGroup.isEmpty { Text("동작 조합이 없습니다.") }
                else { ScrollView { Text(verbatim: workspace.actionGroup).textSelection(.enabled) } }
                Button("닫기") { showingActions = false }.buttonStyle(DooreButtonStyle(.primary))
            }.padding(DooreSize.dialogPadding)
        }
        .alert("장면 저장", isPresented: $saving) {
            Button("취소", role: .cancel) {}
            Button("저장") { Task { await workspace.save(backup: false) } }
            Button("저장 및 백업") { Task { await workspace.save(backup: true) } }
        } message: { Text("수정 전 지도를 별도로 백업할까요?") }
        .alert("삭제", isPresented: $deleteItem, presenting: selected) { item in
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) { workspace.draft.delete(item.id); workspace.selection = nil }
        } message: { item in Text("\(item.number.isEmpty ? item.subtype : item.number) 항목을 삭제할까요?") }
        .alert("장면 라이브러리", isPresented: Binding(get: { workspace.failure != nil },
            set: { if !$0 { workspace.failure = nil } })) {
            Button("닫기") { workspace.failure = nil }
        } message: { Text(LocalizedStringKey(workspace.failure ?? "")) }
        #if os(macOS)
        .focusedSceneValue(\.designUndo, editEnabled && workspace.draft.canUndo ? { workspace.draft.undo() } : nil)
        .focusedSceneValue(\.designRedo, editEnabled && workspace.draft.canRedo ? { workspace.draft.redo() } : nil)
        .focusedSceneValue(\.designSave, editEnabled ? { saving = true } : nil)
        #endif
    }

    private func openFirstSource() {
        guard workspace.source == nil, let scene = robot.scene, let map = robot.activeMap,
              let raw = robot.sceneData, let host = robot.host, let port = robot.port else { return }
        workspace.openSource(scene: scene, map: map, raw: raw, host: host, port: port)
    }

    private var libraryButton: some View {
        Button("장면 라이브러리") { libraryPresented = true }
            .buttonStyle(DooreButtonStyle(.primary, square: true, fullWidth: true))
    }

    private var palette: some View {
        VStack(spacing: DooreSize.tightGap) {
            ScrollView {
                VStack(spacing: DooreSize.tightGap) {
                    ForEach(PaletteGroup.allCases, id: \.self) { group in
                        Text(LocalizedStringKey(group.rawValue)).foregroundStyle(DooreColor.primary).fontWeight(.semibold)
                        Button(LocalizedStringKey(subtype(group))) {
                            tool = tool == group ? nil : group
                            start = nil
                        }
                        .buttonStyle(DooreButtonStyle(tool == group ? .primary : .quiet, square: true, small: true, fullWidth: true))
                        .contextMenu {
                            ForEach(group.subtypes, id: \.self) { choice in
                                Button(LocalizedStringKey(choice)) { choices[group] = choice; tool = group; start = nil }
                            }
                        }
                        .disabled(!editEnabled)
                    }
                    Group {
                        Button("정밀 배치") {}.disabled(true)
                        Button("배치 갱신") {}.disabled(true)
                    }.buttonStyle(DooreButtonStyle(.quiet, square: true, small: true, fullWidth: true))
                    Toggle("가장자리 감지", isOn: $edgeSnap).disabled(!editEnabled)
                    Divider()
                    Text("작업").foregroundStyle(DooreColor.primary).fontWeight(.semibold)
                    Group {
                        Button("작업 묶음") { editingTasks = true }.disabled(!editEnabled)
                        Button("동작 조합") { showingActions = true }.disabled(workspace.source == nil)
                    }.buttonStyle(DooreButtonStyle(.quiet, square: true, small: true, fullWidth: true))
                }
            }
            libraryButton
        }.doorePanel()
    }

    private var canvas: some View {
        VStack(alignment: .leading, spacing: DooreSize.smallGap) {
            ScrollView(.horizontal) {
                HStack(spacing: DooreSize.smallGap) {
                    Text("장면"); Text(verbatim: workspace.source?.scene ?? "—")
                    Text("지도"); Text(verbatim: workspace.map?.name ?? "—")
                    Text("층"); Text(verbatim: workspace.map?.floor ?? "—")
                    if !readOnly {
                        DesignIconButton(title: "저장", icon: "square.and.arrow.down") { saving = true }.disabled(!editEnabled)
                        DesignIconButton(title: "업로드", icon: "square.and.arrow.up") {}.disabled(true)
                        DesignIconButton(title: "실행 취소", icon: "arrow.uturn.backward") { workspace.draft.undo() }
                            .disabled(!editEnabled || !workspace.draft.canUndo)
                        DesignIconButton(title: "다시 실행", icon: "arrow.uturn.forward") { workspace.draft.redo() }
                            .disabled(!editEnabled || !workspace.draft.canRedo)
                    }
                    if let pointer { Text(verbatim: String(format: "(%.2f, %.2f)", pointer.x, pointer.y)).monospacedDigit() }
                    if workspace.draft.changedItemCount > 0 { Text("변경 \(workspace.draft.changedItemCount)건") }
                }
            }
            MapCanvasView(map: workspace.map, pose: sourceMatchesRobot ? robot.pose : nil,
                          selected: $selectedStation, showsStations: false, showsOriginalGeometry: false,
                          showsNavigationPath: sourceMatchesRobot, layers: layers,
                          overlays: overlays, onTap: { tap($0) }, onMove: editEnabled ? move : nil,
                          onInspect: { pointer = $0 }, onAddStroke: editEnabled ? addStroke : nil,
                          onDraw: editEnabled && tool == .base ? paint : nil)
            ScrollView(.horizontal) {
                HStack(spacing: DooreSize.tightGap) {
                    if !readOnly {
                        ForEach([("선", "line.diagonal"), ("펜", "pencil"), ("지우개", "eraser")], id: \.0) { name, symbol in
                            DesignIconButton(title: name, icon: symbol, selected: brush == name && tool == .base) {
                                brush = name
                                start = nil
                            }.disabled(!editEnabled || tool != .base)
                        }
                        Divider()
                    }
                    DesignLayerButtons(layers: $layers)
                }
            }
        }.doorePanel()
    }

    private var sourceMatchesRobot: Bool {
        guard let source = workspace.source else { return false }
        return source.host == robot.host && source.port == robot.port && source.scene == robot.scene?.name
            && source.mapID == robot.poseMapID && robot.state == .ready
    }

    private var overlays: [MapOverlayMark] {
        var marks = workspace.draft.items.map { item in
            let kind: MapOverlayMark.Kind
            switch item.kind {
            case .point: kind = .station
            case .field: kind = .field
            case .guide: kind = .path
            case .paint:
                switch item.subtype {
                case "벽": kind = .wall
                case "미탐색": kind = .unknown
                case "주행 금지": kind = .noGo
                case "교통 통제": kind = .traffic
                default: kind = .free
                }
            }
            return MapOverlayMark(points: item.points.map { MapPose(x: $0.x, y: $0.y, theta: item.heading) },
                                  kind: kind, label: item.number, isSelected: item.id == workspace.selection,
                                  stationType: item.kind == .point ? item.subtype : nil)
        }
        if let start {
            marks.append(MapOverlayMark(points: [start], kind: .station, isSelected: true))
        }
        return marks
    }

    private var properties: some View {
        ScrollView {
            if let item = selected {
                VStack(alignment: .leading, spacing: DooreSize.smallGap) {
                    HStack {
                        Spacer()
                        Text(item.kind == .point ? LocalizedStringKey("스테이션 속성") : LocalizedStringKey(item.subtype)).font(.headline)
                        Spacer()
                    }
                    if item.kind == .point {
                        Text("번호"); TextField("번호", text: binding(item, \.number)).dooreField()
                    }
                    Text("설명"); TextField("설명", text: binding(item, \.description)).dooreField()
                    if let p = item.points.first {
                        Text("위치")
                        HStack {
                            coordinateField("X", point: p, item: item, xAxis: true)
                            coordinateField("Y", point: p, item: item, xAxis: false)
                        }
                    }
                    if item.kind == .point {
                        Text("방향 (rad)")
                        TextField("방향 (rad)", value: binding(item, \.heading), format: .number).dooreField()
                        Picker("도착 방식", selection: binding(item, \.arrival)) {
                            Text("—").tag(String?.none)
                            ForEach(["대략 도착", "정밀 도착"], id: \.self) { Text(LocalizedStringKey($0)).tag(Optional($0)) }
                        }
                        Text("도킹 검증").foregroundStyle(DooreColor.primary)
                        ForEach(["광전 센서", "자기 테이프", "라이다 특징"], id: \.self) { check in
                            Toggle(LocalizedStringKey(check), isOn: Binding(get: { selected?.dockingChecks?.contains(check) == true },
                                set: { enabled in
                                    guard var next = selected else { return }
                                    var checks = next.dockingChecks ?? []
                                    if enabled { checks.insert(check) } else { checks.remove(check) }
                                    next.dockingChecks = checks
                                    workspace.draft.put(next)
                                }))
                        }
                    }
                    if item.kind == .field {
                        Text("속도 제한")
                        TextField("속도 제한", value: binding(item, \.speedLimit), format: .number).dooreField()
                        Text("허용 로봇 수")
                        TextField("허용 로봇 수", value: binding(item, \.capacity), format: .number).dooreField()
                    } else if item.kind == .guide {
                        Text("폭")
                        TextField("폭", value: binding(item, \.width), format: .number).dooreField()
                        Toggle("회피 허용", isOn: Binding(get: { selected?.allowsAvoidance == true }, set: { value in
                            guard var next = selected else { return }
                            next.allowsAvoidance = value
                            workspace.draft.put(next)
                        }))
                    }
                    if !readOnly {
                        Button("삭제") { deleteItem = true }.buttonStyle(DooreButtonStyle(.danger, small: true))
                    }
                }.disabled(!editEnabled)
            } else {
                Text("지도에서 속성을 확인할 항목을 선택하세요.").foregroundStyle(DooreColor.inkSoft)
            }
        }.frame(maxWidth: .infinity).doorePanel()
    }

    private func coordinateField(_ title: LocalizedStringKey, point: DraftPoint, item: DraftItem, xAxis: Bool) -> some View {
        TextField(title, value: Binding(get: { xAxis ? point.x : point.y }, set: { value in
            workspace.draft.move(item.id, dx: xAxis ? value - point.x : 0, dy: xAxis ? 0 : value - point.y)
        }), format: .number).dooreField().monospacedDigit()
    }

    private func binding<T>(_ item: DraftItem, _ path: WritableKeyPath<DraftItem, T>) -> Binding<T> {
        Binding(get: { (workspace.draft.items.first { $0.id == item.id } ?? item)[keyPath: path] },
                set: { value in
                    guard var updated = workspace.draft.items.first(where: { $0.id == item.id }) else { return }
                    updated[keyPath: path] = value
                    workspace.draft.put(updated)
                })
    }

    private func nearest(_ location: DraftPoint, paintOnly: Bool = false) -> DraftItem? {
        let visible = workspace.draft.items.filter {
            switch $0.kind {
            case .point: !paintOnly && layers.contains("스테이션")
            case .field: !paintOnly && layers.contains("구역")
            case .guide: !paintOnly && layers.contains("경로")
            case .paint: true
            }
        }
        let nearest = visible.map { ($0, $0.distance(to: location)) }.min { $0.1 < $1.1 }
        return nearest.flatMap { $0.1 <= (workspace.map?.resolution ?? 0) * 8 ? $0.0 : nil }
    }

    private func point(_ pose: MapPose) -> DraftPoint {
        let value = DraftPoint(x: pose.x, y: pose.y)
        guard edgeSnap, let map = workspace.map, let resolution = map.resolution else { return value }
        // Snap to the nearest edge vertex in the scene. All coordinates are in metres.
        let vertices = (map.fields + map.guides).flatMap { $0 }.map { DraftPoint(x: $0.x, y: $0.y) }
        let closest = vertices.min { hypot($0.x-value.x, $0.y-value.y) < hypot($1.x-value.x, $1.y-value.y) }
        if let closest, hypot(closest.x-value.x, closest.y-value.y) <= resolution * 4 { return closest }
        return value
    }

    private func tap(_ pose: MapPose) {
        guard editEnabled, let tool else {
            workspace.selection = nearest(.init(x: pose.x, y: pose.y))?.id
            return
        }
        switch tool {
        case .point: add(.point, points: [point(pose)])
        case .base where brush != "선": paint([pose])
        default:
            if let first = start { addStroke(first, pose); start = nil }
            else { start = pose }
        }
    }

    private func move(_ from: MapPose, _ to: MapPose) {
        guard editEnabled, let item = nearest(.init(x: from.x, y: from.y)) else { return }
        workspace.selection = item.id
        workspace.draft.move(item.id, dx: to.x - from.x, dy: to.y - from.y)
    }

    private func addStroke(_ from: MapPose, _ to: MapPose) {
        guard editEnabled, let tool else { return }
        let a = point(from), b = point(to)
        switch tool {
        case .base: paint([from, to])
        case .point: add(.point, points: [b])
        case .guide: if a != b { add(.guide, points: [a, b]) }
        case .field:
            guard a.x != b.x && a.y != b.y else { return }
            add(.field, points: [a, .init(x: b.x, y: a.y), b, .init(x: a.x, y: b.y)])
        }
        start = nil
    }

    private func paint(_ samples: [MapPose]) {
        guard editEnabled, let first = samples.first, let last = samples.last else { return }
        if brush == "지우개" {
            let ids = Set(samples.compactMap { nearest(point($0), paintOnly: true)?.id })
            for id in ids { workspace.draft.delete(id) }
        } else {
            let vertices = brush == "선" && samples.count > 1 ? [first, last] : samples
            add(.paint, points: vertices.map(point))
        }
        start = nil
    }

    private func add(_ kind: DraftItem.Kind, points: [DraftPoint]) {
        guard let tool else { return }
        var next = DraftItem(kind: kind, subtype: subtype(tool), points: points)
        if kind == .point {
            let occupied = Set(workspace.draft.items.map(\.number))
            var number = 1
            while occupied.contains(String(number)) { number += 1 }
            next.number = String(number)
            next.dockingChecks = []
            layers.insert("스테이션")
        } else if kind == .field { layers.insert("구역") }
        else if kind == .guide { layers.insert("경로") }
        workspace.draft.put(next)
        workspace.selection = next.id
    }
}
