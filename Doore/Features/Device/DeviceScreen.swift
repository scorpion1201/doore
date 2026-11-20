import SwiftUI
import WooshKit

struct DeviceScreen: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var speech = ""
    @State private var stepType = "직진"
    @State private var avoid = true
    @State private var distance = ""
    @State private var angle = ""
    @State private var speed = ""
    @State private var custom = ""

    private var step: RobotSettingChange? {
        let modes = ["직진": 1, "회전": 2, "평행 이동": 3, "대각 이동": 4]
        guard let mode = modes[stepType], let value = Float(distance), let speed = Float(speed),
              let heading = mode == 4 ? Float(angle) : 0 else { return nil }
        return .step(mode: mode, value: value, speed: speed, angle: heading, avoid: avoid)
    }

    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout(alignment: .top))
        layout {
            Text("제어").font(.title3).frame(width: compact ? nil : DooreSize.tabColumn)
                .padding(.vertical, DooreSize.panelPadding).background(DooreColor.surface)
            ScrollView {
                VStack(alignment: .leading, spacing: DooreSize.gap) {
                    if robot.state != .ready {
                        RobotRegionState(message: "로봇에 연결하면 제어할 장치가 여기에 표시됩니다.")
                    } else {
                        GroupBox("음성") {
                            VStack(alignment: .leading) {
                                TextField("내용", text: $speech).dooreField()
                                HStack {
                                    Button("실행") { Task { await robot.setting(.speech(speech)) } }
                                        .buttonStyle(DooreButtonStyle(.primary)).disabled(!RobotSettingChange.speech(speech).allows(robot.snapshot))
                                    Button("오디오 재생") {}.buttonStyle(DooreButtonStyle(.quiet)).disabled(true)
                                    Button("오디오 정지") {}.buttonStyle(DooreButtonStyle(.quiet)).disabled(true)
                                }
                            }
                        }
                        GroupBox("스텝 이동") {
                            VStack(alignment: .leading) {
                                Picker("종류", selection: $stepType) {
                                    ForEach(["직진", "회전", "평행 이동", "대각 이동"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                                }
                                Toggle("회피 사용", isOn: $avoid)
                                TextField(stepType == "회전" ? LocalizedStringKey("각도 (rad)") : LocalizedStringKey("거리 (m)"), text: $distance).dooreField()
                                TextField(stepType == "회전" ? LocalizedStringKey("속도 (rad/s)") : LocalizedStringKey("속도 (m/s)"), text: $speed).dooreField()
                                if stepType == "대각 이동" { TextField("대각 각도 (rad)", text: $angle).dooreField() }
                                HStack {
                                    Button("실행") { if let step { Task { await robot.setting(step) } } }
                                        .buttonStyle(DooreButtonStyle(.primary))
                                        .disabled(step?.allows(robot.snapshot) != true)
                                    Button("취소") { Task { await robot.setting(.cancelStep) } }
                                        .buttonStyle(DooreButtonStyle(.quiet))
                                }
                            }
                        }
                        GroupBox("사용자 정의") {
                            VStack(alignment: .leading) {
                                TextField("내용", text: $custom, axis: .vertical).dooreField()
                                Button("실행") {}.buttonStyle(DooreButtonStyle(.primary))
                            }.disabled(true)
                        }
                        Text("추가 장치 제어는 로봇 모델별 지원 여부를 확인해야 합니다.").foregroundStyle(DooreColor.inkSoft)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).doorePanel()
            }
        }
    }
}
