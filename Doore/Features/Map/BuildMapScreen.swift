import SwiftUI
import WooshKit

struct BuildMapScreen: View {
    let operation: MapBuildOperation
    let sceneName: String
    let map: MapModel?
    let stationEditing: Bool
    var availableMapNames: [String] = []
    let close: () -> Void
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var selected: String?
    @State private var name = ""
    @State private var stationKind = "스테이션"
    @State private var stationNo = ""
    @State private var precise = false
    @State private var edge = false
    @State private var overview = false
    @State private var confirm: MapBuildOperation?
    @State private var askName = false
    @State private var deleting: String?
    private var mapping: Bool { robot.stateLabel == "지도 작성 중" }
    private var modeAllowed: Bool { robot.controlModeLabel == "자동" && robot.workModeLabel == "배치" }

    var body: some View {
        ScrollView {
            VStack {
                HStack { Spacer(); Button { close() } label: { Image(systemName: "xmark") }.accessibilityLabel("닫기") }
                ModeBanner(requiredWork: "배치", mode: 1)
                let layout = compact ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
                layout {
                    if DriveLayout.isPhone {
                        TeleoperationPad { mapRegion }.disabled(driveCovered)
                    } else {
                        mapRegion
                    }
                    if mapping || stationEditing {
                        VStack(alignment: .leading) {
                            Picker("종류", selection: $stationKind) {
                                ForEach(["스테이션", "충전기", "주차 자리"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                            }
                            TextField("번호", text: $stationNo).dooreField()
                            Toggle("정밀 배치", isOn: $precise).disabled(true)
                            Toggle("가장자리 감지", isOn: $edge).disabled(true)
                            Text("정밀 배치와 가장자리 감지는 로봇에서 지원 여부를 확인해야 합니다.").foregroundStyle(DooreColor.inkSoft)
                            Button("스테이션 추가") {
                                guard let map else { return }
                                let kind: StationChange.Kind = stationKind == "충전기" ? .charger : stationKind == "주차 자리" ? .parkspot : .station
                                Task { await robot.addStation(mapID: map.id, number: stationNo, kind: kind) }
                            }.buttonStyle(DooreButtonStyle(.primary))
                                .disabled(!modeAllowed || robot.state != .ready || robot.pose == nil || robot.poseMapID != map?.id || map?.id != robot.currentMapID || stationNo.isEmpty || map?.stations.contains { $0.number == stationNo } != false)
                            Button("스테이션 삭제") { deleting = selected }.buttonStyle(DooreButtonStyle(.danger))
                                .disabled(!modeAllowed || robot.state != .ready || selected == nil || map?.id != robot.currentMapID)
                        }.frame(width: compact ? nil : DooreSize.tabColumn)
                    }
                }
                if DriveLayout.isPhone {
                    driveControls
                } else {
                    TeleoperationPad { driveControls }.disabled(driveCovered)
                }
                if !stationEditing {
                    HStack {
                        if mapping {
                            Button("저장") { confirm = .save }.buttonStyle(DooreButtonStyle(.primary))
                            Button("취소") { confirm = .cancel }.buttonStyle(DooreButtonStyle(.quiet))
                        } else {
                            Button("시작") { name = operation == .update ? map?.name ?? "" : ""; askName = true }
                                .buttonStyle(DooreButtonStyle(.primary))
                        }
                    }.disabled(!modeAllowed || robot.state != .ready)
                }
            }.doorePanel()
        }
        .sensorFeeds(overview ? [.scannerData, .buildMapData] : [.buildMapData])
        .driveOrientation()
        .alert("선택한 스테이션을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { number in
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) { if let map { Task { await robot.deleteStation(mapID: map.id, number: number) } } }
        } message: { number in Text(verbatim: number) }
        .alert("지도 이름", isPresented: $askName) {
            TextField("이름", text: $name)
            Button("취소", role: .cancel) {}
            Button("확인") {
                Task { await robot.perform(.buildMap(operation, scene: sceneName, name: name)) }
            }.disabled(!validName)
        } message: { Text(verbatim: sceneName) }
        .alert(confirm == .save ? LocalizedStringKey("작성한 지도를 저장할까요?") : LocalizedStringKey("지도 작성을 취소할까요?"),
               isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { op in
            Button("취소", role: .cancel) {}
            Button("확인") { Task { await robot.perform(.buildMap(op, scene: sceneName, name: name)) } }
        }
    }

    @ViewBuilder private var mapRegion: some View {
        if mapping {
            if let frame = robot.feeds.mapFrame {
                VStack {
                    Text("지도 데이터 수신")
                    Text(verbatim: "\(frame.width) × \(frame.height) px · \(frame.payloadBytes) B").monospacedDigit()
                    Text("실시간 지도 이미지 형식은 확인이 필요합니다.").foregroundStyle(DooreColor.inkSoft)
                }.frame(maxWidth: .infinity, minHeight: DooreSize.mapMinimum)
            } else if robot.feeds.failures.contains(.buildMapData) {
                Text("지도 데이터 구독에 실패했습니다.").foregroundStyle(DooreColor.danger)
            } else {
                RobotRegionState(message: "로봇에 연결하면 지도와 스테이션이 여기에 표시됩니다.",
                                 empty: "실시간 지도 데이터를 기다리는 중입니다.")
                    .frame(minHeight: DooreSize.mapMinimum)
            }
        } else {
            MapCanvasView(map: map, pose: robot.poseMapID == map?.id ? robot.pose : nil,
                          selected: $selected, followsRobot: !overview)
        }
    }

    private var driveControls: some View {
        VStack {
            WorkModeSelector()
            Toggle("전체 보기", isOn: $overview)
            if overview { ScannerReadout() }
            DriveOptions()
        }
    }

    private var driveCovered: Bool { confirm != nil || askName || deleting != nil }

    private var validName: Bool {
        guard !name.isEmpty, name.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "~_#=")).inverted) == nil else { return false }
        return operation == .update ? map?.name == name : !availableMapNames.contains(name)
    }
}
