import SwiftUI
import WooshKit
#if os(iOS)
import UIKit
#endif

struct DesignSceneLibrary: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RobotStore.self) private var robot
    @Environment(SceneEditingWorkspace.self) private var workspace
    @State private var remote = SceneStore()
    @State private var local = true
    @State private var localSelection: LocalScene?
    @State private var robotSelection: String?
    @State private var confirmDiscard = false
    @State private var confirmDelete = false

    private var canOpen: Bool {
        if local { return localSelection != nil }
        return remote.scene?.map(id: robotSelection) != nil && robot.state == .ready && !remote.busy
    }

    var body: some View {
        VStack(spacing: DooreSize.compactGap) {
            Text("장면 라이브러리").font(.headline)
            Picker("장면 라이브러리", selection: $local) {
                Text("로컬 장면").tag(true)
                Text("로봇 장면").tag(false)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: DooreSize.tightGap) {
                    if local {
                        if workspace.library.isEmpty { Text("저장한 장면이 없습니다.") }
                        ForEach(workspace.library) { file in
                            choice(file.scene + " · " + file.mapName + " · " + file.host,
                                   selected: file == localSelection) { localSelection = file }
                        }
                    } else if robot.state == .ready {
                        if remote.busy { ProgressView("불러오는 중") }
                        if remote.failed {
                            Button("다시 시도") { Task { await remote.reload(robot) } }.buttonStyle(DooreButtonStyle(.line))
                        }
                        ForEach(remote.entries, id: \.name) { scene in
                            choice(scene.name, selected: remote.scene?.name == scene.name) {
                                robotSelection = nil
                                Task { await remote.select(scene.name, robot: robot) }
                            }
                        }
                        if let scene = remote.scene {
                            Divider()
                            ForEach(scene.maps) { map in
                                choice(map.name, selected: map.id == robotSelection) { robotSelection = map.id }
                            }
                        }
                    } else {
                        RobotRegionState(message: "로봇에 연결하면 장면 목록이 여기에 표시됩니다.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: DooreSize.dialogScrollLimit)
            HStack {
                Button("닫기") { dismiss() }.buttonStyle(DooreButtonStyle(.quiet))
                Button("삭제") { confirmDelete = true }.buttonStyle(DooreButtonStyle(.danger))
                    .disabled(!local || localSelection == nil || workspace.busy || isPhone)
                Button("열기") {
                    if workspace.hasUnsavedEdits { confirmDiscard = true } else { open() }
                }.buttonStyle(DooreButtonStyle(.primary)).disabled(!canOpen || workspace.busy)
            }
        }
        .padding(DooreSize.dialogPadding)
        .task { await workspace.refresh() }
        .task(id: local ? nil : robot.state) {
            if !local { await remote.reload(robot) }
        }
        .onChange(of: remote.scene?.name) { _, _ in robotSelection = remote.scene?.maps.first?.id }
        .alert("장면 열기", isPresented: $confirmDiscard) {
            Button("취소", role: .cancel) {}
            Button("확인") { open() }
        } message: { Text("저장하지 않은 변경 사항을 버리고 장면을 열까요?") }
        .alert("장면 삭제", isPresented: $confirmDelete, presenting: localSelection) { file in
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) {
                Task { await workspace.delete(file); localSelection = nil }
            }
        } message: { file in Text("\(file.scene) · \(file.mapName) 장면을 삭제할까요?") }
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private func choice(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(verbatim: name); Spacer(); if selected { Image(systemName: "checkmark") } }
                .padding(DooreSize.compactPanelPadding)
                .background(selected ? DooreColor.primaryTint : DooreColor.well,
                            in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
        }.buttonStyle(.plain)
    }

    private func open() {
        if local, let localSelection {
            Task { await workspace.load(localSelection); if workspace.failure == nil { dismiss() } }
        } else if let scene = remote.scene, let map = scene.map(id: robotSelection),
                  let raw = remote.sourceData, let host = robot.host, let port = robot.port {
            workspace.openSource(scene: scene, map: map, raw: raw, host: host, port: port)
            if workspace.failure == nil { dismiss() }
        }
    }
}
