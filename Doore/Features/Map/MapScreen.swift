import SwiftUI
import WooshKit

struct MapScreen: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var directory = SceneStore()
    @State private var dialog: MapDialog?
    @State private var mapID: String?
    @State private var selected: String?
    @State private var coordinate: MapPose?
    @State private var detail = false
    @State private var building: MapBuildOperation?
    @State private var stationEditing = false

    private var scene: SceneModel? { directory.scene }
    private var map: MapModel? {
        scene?.map(id: mapID) ?? (scene?.name == robot.snapshot.sceneName ? scene?.map(id: robot.currentMapID) : nil)
            ?? scene?.maps.first
    }
    private var activeMap: Bool { scene?.name == robot.snapshot.sceneName && map?.id == robot.currentMapID }
    private var ready: Bool { robot.state == .ready && !directory.busy }
    private var names: [String] { directory.entries.first(where: { $0.name == scene?.name })?.maps ?? [] }

    var body: some View {
        Group {
            if let building, let scene {
                BuildMapScreen(operation: building, sceneName: scene.name, map: map, stationEditing: stationEditing,
                               availableMapNames: names) {
                    self.building = nil
                    Task { await directory.reload(robot) }
                }
            } else if compact {
                if detail {
                    ScrollView {
                        VStack(alignment: .leading) {
                            Button("장면 목록") { detail = false }.buttonStyle(DooreButtonStyle(.line))
                            mapDetail
                        }
                    }
                } else { sceneList }
            } else {
                HStack(spacing: DooreSize.gap) {
                    sceneList.frame(width: DooreSize.sidePanel)
                    mapDetail
                }
            }
        }
        .task(id: robot.state) {
            if robot.state != .ready {
                building = nil
                dialog = nil
                mapID = nil
                detail = false
            }
            await directory.reload(robot)
        }
        .onChange(of: scene?.name) { _, _ in mapID = nil; selected = nil; coordinate = nil }
        .onChange(of: map?.id) { _, _ in selected = nil; coordinate = nil }
        .sheet(item: $dialog) { target in
            MapChangeDialog(target: target, sceneNames: directory.entries.map(\.name), mapNames: names) { operation in
                dialog = nil
                Task {
                    let preferred: String?
                    if case .renameScene(_, let name) = operation { preferred = name } else { preferred = scene?.name }
                    await directory.apply(operation, robot: robot, preferred: preferred)
                }
            }
        }
    }

    private var sceneList: some View {
        VStack(alignment: .leading, spacing: DooreSize.smallGap) {
            Button("＋ 장면 추가") {}.buttonStyle(DooreButtonStyle(.primary, fullWidth: true)).disabled(true)
            if !directory.entries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(directory.entries) { entry in
                            Button {
                                Task {
                                    await directory.select(entry.name, robot: robot)
                                    if directory.scene?.name == entry.name { detail = true }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: entry.name).font(.headline)
                                        Text("지도 \(entry.maps.count)장")
                                    }
                                    Spacer()
                                    if entry.name == robot.snapshot.sceneName { Text("사용 중").foregroundStyle(DooreColor.primary) }
                                    if compact { Image(systemName: "chevron.right") }
                                }.padding(DooreSize.compactPanelPadding)
                                    .background(DooreColor.well, in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                                    .overlay {
                                        if entry.name == scene?.name {
                                            RoundedRectangle(cornerRadius: DooreSize.rowRadius)
                                                .strokeBorder(DooreColor.primary, lineWidth: DooreSize.outline)
                                        }
                                    }
                            }.buttonStyle(.plain).disabled(!ready)
                        }
                    }
                }
            } else if !directory.busy && !directory.failed {
                RobotRegionState(message: "로봇에 연결하면 장면 목록이 여기에 표시됩니다.", empty: "표시할 장면이 없습니다.")
            }
            if directory.busy { ProgressView("요청 중…") }
            if directory.failed {
                Button("다시 시도") { Task { await directory.reload(robot) } }
                    .buttonStyle(DooreButtonStyle(.line))
            }
            Spacer()
            HStack {
                changeButton("장면 이름 변경", .renameScene)
                changeButton("장면 삭제", .deleteScene, danger: true)
            }
        }.doorePanel()
    }

    private var mapDetail: some View {
        VStack(spacing: DooreSize.smallGap) {
            let layout = compact ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
            layout {
                MapCanvasView(map: map, pose: scene?.name == robot.snapshot.sceneName && robot.poseMapID == map?.id ? robot.pose : nil, selected: $selected,
                              showsNavigationPath: scene?.name == robot.snapshot.sceneName, onInspect: { coordinate = $0 })
                VStack {
                    Text(verbatim: coordinate.map { String(format: "X %.2f  Y %.2f", $0.x, $0.y) } ?? "X —  Y —")
                        .monospacedDigit()
                    changeButton("지도 이름 변경", .renameMap, mapAction: true)
                    buildButton("지도 추가", .add)
                    buildButton("지도 갱신", .update)
                    changeButton("지도 사용", .useMap, mapAction: true)
                    changeButton("지도 삭제", .deleteMap, mapAction: true, danger: true)
                    Button("스테이션 편집") { stationEditing = true; building = .update }
                        .buttonStyle(DooreButtonStyle(.primary, square: true, fullWidth: true)).disabled(!ready || !activeMap || map == nil)
                }.frame(width: compact ? nil : DooreSize.toolColumn)
            }
            MapCards(scene: scene, map: map, select: { mapID = $0.id })
        }.doorePanel()
    }

    private func changeButton(_ label: LocalizedStringKey, _ kind: MapDialog.Kind,
                              mapAction: Bool = false, danger: Bool = false) -> some View {
        Button(label) {
            guard let scene else { return }
            dialog = MapDialog(kind: kind, title: label, scene: scene.name, map: map?.name ?? "")
        }
        .buttonStyle(DooreButtonStyle(danger ? .danger : .quiet, square: mapAction, fullWidth: mapAction))
        .disabled(!ready || scene == nil || (mapAction && map == nil))
    }

    private func buildButton(_ label: LocalizedStringKey, _ operation: MapBuildOperation) -> some View {
        Button(label) { stationEditing = false; building = operation }
            .buttonStyle(DooreButtonStyle(.quiet, square: true, fullWidth: true))
            .disabled(!ready || scene == nil || (operation == .update && map == nil))
    }
}

struct MapCards: View {
    let scene: SceneModel?
    let map: MapModel?
    let select: (MapModel) -> Void
    @Environment(RobotStore.self) private var robot

    var body: some View {
        if let scene, !scene.maps.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(scene.maps) { item in
                        Button { select(item) } label: {
                            HStack {
                                MapThumbnail(data: item.imageData)
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(verbatim: item.name).font(.headline)
                                        if scene.name == robot.snapshot.sceneName && item.id == robot.currentMapID { Text("사용 중").foregroundStyle(DooreColor.primary) }
                                    }
                                    Text(verbatim: "ID \(item.id)")
                                    if let floor = item.floor { LabeledContent("층", value: floor) }
                                    if let version = item.version { LabeledContent("버전", value: version) }
                                    if let modified = item.modified { LabeledContent("수정", value: modified) }
                                    if let point = item.origin { LabeledContent("원점", value: String(format: "(%.2f, %.2f)", point.x, point.y)) }
                                }
                            }.padding(DooreSize.smallGap)
                                .background(DooreColor.well, in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                                .overlay {
                                    if item.id == map?.id {
                                        RoundedRectangle(cornerRadius: DooreSize.rowRadius)
                                            .strokeBorder(DooreColor.primary, lineWidth: DooreSize.outline)
                                    }
                                }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MapDialog: Identifiable {
    enum Kind { case renameScene, deleteScene, renameMap, deleteMap, useMap }
    let id = UUID()
    let kind: Kind
    let title: LocalizedStringKey
    let scene: String
    let map: String
}

private struct MapChangeDialog: View {
    @Environment(\.dismiss) private var dismiss
    let target: MapDialog
    let sceneNames: [String]
    let mapNames: [String]
    let submit: (SceneOperation) -> Void
    @State private var replacement = ""
    @State private var reset = false

    private var renaming: Bool { target.kind == .renameScene || target.kind == .renameMap }
    private var sceneOnly: Bool { target.kind == .renameScene || target.kind == .deleteScene }
    private var valid: Bool {
        guard renaming else { return true }
        return SceneOperation.validNewName(replacement) && !(sceneOnly ? sceneNames : mapNames).contains(replacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DooreSize.gap) {
            Text(target.title).font(.title2.bold())
            Text(verbatim: sceneOnly ? target.scene : "\(target.scene) / \(target.map)")
            if renaming { TextField("이름", text: $replacement).textFieldStyle(.roundedBorder) }
            if target.kind == .useMap { Toggle("동시에 로봇 초기화", isOn: $reset) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.buttonStyle(DooreButtonStyle(.quiet))
                Button("확인") {
                    switch target.kind {
                    case .renameScene: submit(.renameScene(scene: target.scene, to: replacement))
                    case .deleteScene: submit(.deleteScene(scene: target.scene))
                    case .renameMap: submit(.renameMap(scene: target.scene, map: target.map, to: replacement))
                    case .deleteMap: submit(.deleteMap(scene: target.scene, map: target.map))
                    case .useMap: submit(.useMap(scene: target.scene, map: target.map, reset: reset))
                    }
                }
                .buttonStyle(DooreButtonStyle(target.kind == .deleteScene || target.kind == .deleteMap ? .danger : .primary))
                .disabled(!valid)
            }
        }.padding(DooreSize.panelPadding)
    }
}
