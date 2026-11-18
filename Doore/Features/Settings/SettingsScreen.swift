import SwiftUI
import WooshKit

struct SettingsScreen: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var current = "로봇"
    @State private var detail = false
    private let tabs = ["로봇", "원격 조종", "초기화", "WIFI", "정보"]

    var body: some View {
        if compact {
            if detail {
                VStack(alignment: .leading) {
                    Button { detail = false } label: { Label("설정", systemImage: "chevron.left") }
                        .buttonStyle(.plain)
                    content
                }.doorePanel()
            } else { tabList.doorePanel() }
        } else {
            HStack(spacing: 0) {
                tabList.frame(width: DooreSize.tabColumn)
                content.doorePanel()
            }
        }
    }

    private var tabList: some View {
        ScrollView {
            VStack(spacing: DooreSize.tightGap) {
                ForEach(tabs, id: \.self) { tab in
                    Button { current = tab; detail = true } label: {
                        HStack {
                            Text(LocalizedStringKey(tab)).fontWeight(tab == current ? .semibold : .regular)
                            if compact { Spacer(); Image(systemName: "chevron.right") }
                        }.padding(.horizontal, DooreSize.panelPadding)
                            .frame(maxWidth: .infinity, minHeight: compact ? DooreSize.buttonHeight : DooreSize.tabHeight)
                            .background(current == tab ? DooreColor.surface : DooreColor.tab,
                                        in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DooreSize.gap) {
                switch current {
                case "원격 조종": TeleopSettings()
                case "초기화": InitSettings()
                case "WIFI": WiFiSettings()
                case "정보": AboutSettings()
                default: RobotSettings()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkModeSelector: View {
    @Environment(RobotStore.self) private var robot
    var body: some View {
        Picker("작업 모드", selection: Binding(
            get: { robot.snapshot.workMode ?? 0 },
            set: { mode in Task { await robot.switchWorkMode(mode) } }
        )) {
            if robot.snapshot.workMode == nil { Text(verbatim: "—").tag(0) }
            Text("배치").tag(1)
            Text("작업").tag(2)
            Text("관제").tag(3)
        }.pickerStyle(.segmented).disabled(robot.state != .ready || robot.snapshot.controlMode != 1)
    }
}

private struct RobotSettings: View {
    @Environment(RobotStore.self) private var robot
    @State private var nameDraft = ""
    @State private var server = ""
    @State private var port = ""

    var body: some View {
        if robot.state != .ready {
            RobotRegionState(message: "로봇에 연결하면 설정이 여기에 표시됩니다.")
        }
        GroupBox("모드") {
            VStack(alignment: .leading) {
                Picker("제어", selection: Binding(
                    get: { robot.snapshot.controlMode ?? 0 },
                    set: { value in Task { await robot.setting(.controlMode(value)) } }
                )) {
                    if robot.snapshot.controlMode == nil { Text(verbatim: "—").tag(0) }
                    Text("자동").tag(1); Text("수동").tag(2); Text("정비").tag(3)
                }.disabled(robot.snapshot.controlMode == nil)
                WorkModeSelector()
                flag("정차 유지", .hold)
                TextField("관제 IP", text: $server).dooreField()
                HStack {
                    TextField("관제 포트", text: $port).dooreField()
                    Button("수정") {
                        guard let value = UInt32(port) else { return }
                        Task { await robot.setting(.server(server, value)) }
                    }.buttonStyle(DooreButtonStyle(.primary, small: true))
                        .disabled(UInt32(port).map { !RobotSettingChange.server(server, $0).allows(robot.snapshot) } ?? true)
                }
            }
        }
        GroupBox("정보") {
            VStack(alignment: .leading) {
                HStack {
                    TextField("이름", text: $nameDraft).dooreField()
                    Button("수정") { Task { await robot.setting(.identity(nameDraft)) } }
                        .buttonStyle(DooreButtonStyle(.primary, small: true))
                        .disabled(!RobotSettingChange.identity(nameDraft).allows(robot.snapshot))
                }
                LabeledContent("번호", value: robot.snapshot.number ?? "—")
                LabeledContent("모델", value: robot.snapshot.modelName ?? "—")
                if let l = robot.snapshot.length, let w = robot.snapshot.width, let h = robot.snapshot.height {
                    LabeledContent("크기", value: "\(l) × \(w) × \(h) mm")
                }
                LabeledContent("시스템", value: robot.snapshot.systemVersion ?? "—")
                if let p = robot.pose { LabeledContent("위치", value: String(format: "(%.2f, %.2f, %.2f)", p.x, p.y, p.theta)) }
                if let l = robot.snapshot.linear, let a = robot.snapshot.angular {
                    LabeledContent("속도", value: String(format: "%.2f m/s, %.2f rad/s", l, a))
                }
                LabeledContent("배터리", value: robot.battery.map { "\($0)%" } ?? "—")
            }.monospacedDigit()
        }
        GroupBox("구성") {
            VStack(alignment: .leading) {
                flag("자율 충전", .autoCharge); flag("자율 주차", .autoPark); flag("화물 감지", .goodsCheck)
                flag("케이블 작업", .cableMotion); flag("점유 상태", .occupancy); flag("호출 차단", .muteCall)
                flag("프로그램 음소거", .programMute)
                threshold("만충전", "full", "이 값보다 높아지면 자율 충전을 끝냅니다.")
                threshold("대기", "idle", "충전 중 이 값을 넘고 작업이 있으면 작업을 이어 갑니다.")
                threshold("저전력", "low", "이 값보다 낮아지면 자율 충전을 시작합니다.")
            }
        }
        .onChange(of: robot.name, initial: true) { _, value in nameDraft = value ?? "" }
        .onChange(of: robot.snapshot.serverHost, initial: true) { _, value in server = value ?? "" }
        .onChange(of: robot.snapshot.serverPort, initial: true) { _, value in port = value.map { String($0) } ?? "" }
    }

    private func flag(_ label: LocalizedStringKey, _ flag: RobotSettingChange.Flag) -> some View {
        let reported = robot.snapshot.reported(flag)
        return Toggle(label, isOn: Binding(
            get: { reported ?? false }, set: { value in Task { await robot.setting(.flag(flag, value)) } }
        )).disabled(reported == nil || robot.state != .ready)
    }

    private func threshold(_ label: LocalizedStringKey, _ key: String, _ hint: LocalizedStringKey) -> some View {
        let values = robot.snapshot.thresholds
        return VStack(alignment: .leading) {
            ReportedSlider(title: label, reported: values[key], tint: key == "low" ? DooreColor.danger : DooreColor.primary) { new in
                var updated = robot.snapshot.thresholds
                updated[key] = new
                guard let low = updated["low"].flatMap(UInt32.init(exactly:)),
                      let idle = updated["idle"].flatMap(UInt32.init(exactly:)),
                      let full = updated["full"].flatMap(UInt32.init(exactly:)),
                      let alarm = updated["alarm"].flatMap(UInt32.init(exactly:)) else { return }
                Task { await robot.setting(.thresholds(low: low, idle: idle, full: full, alarm: alarm)) }
            }.disabled(!["low", "idle", "full", "alarm"].allSatisfy { values[$0] != nil })
            Text(hint).foregroundStyle(DooreColor.inkSoft)
        }
    }
}

private struct ReportedSlider: View {
    let title: LocalizedStringKey
    let reported: Int?
    var tint = DooreColor.primary
    let submit: (Int) -> Void
    @State private var draft: Double?

    var body: some View {
        VStack {
            LabeledContent(title, value: (draft.map(Int.init) ?? reported).map { "\($0)%" } ?? "—")
            Slider(value: Binding(get: { draft ?? Double(reported ?? 0) }, set: { draft = $0 }),
                   in: 0...100, step: 1) { Text(title) } onEditingChanged: { changing in
                if !changing, let draft {
                    submit(Int(draft)); self.draft = nil
                }
            }.tint(tint).disabled(reported == nil)
        }
    }
}

struct DriveOptions: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.compactLayout) private var compact
    var body: some View {
        @Bindable var settings = settings
        let layout = compact ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
        layout {
            Picker("구동", selection: $settings.driveMode) {
                ForEach(["세로", "가로", "전방향"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
            }
            Picker("선속도", selection: $settings.linearSpeed) {
                ForEach([0.1, 0.2, 0.3, 0.4, 0.5], id: \.self) { Text(verbatim: String(format: "%.1f m/s", $0)).tag($0) }
            }
            Picker("각속도", selection: $settings.angularSpeed) {
                ForEach([0.1, 0.2, 0.3, 0.4, 0.5], id: \.self) { Text(verbatim: String(format: "%.1f rad/s", $0)).tag($0) }
            }
        }
    }
}

private struct TeleopSettings: View {
    @Environment(RobotStore.self) private var robot
    @State private var selected: String?
    @State private var overview = false
    private var map: some View {
        MapCanvasView(map: robot.activeMap, pose: robot.poseMapID == robot.activeMap?.id ? robot.pose : nil,
                      selected: $selected, followsRobot: !overview)
    }

    private var controls: some View {
        VStack {
            Toggle("전체 보기", isOn: $overview)
            if overview { ScannerReadout() }
            DriveOptions()
        }
    }

    var body: some View {
        VStack {
            if DriveLayout.isPhone {
                TeleoperationPad { map }
                controls
            } else {
                map
                TeleoperationPad { controls }
            }
        }
        .sensorFeeds(overview ? [.scannerData] : [])
        .driveOrientation()
    }
}

private struct AboutSettings: View {
    @Environment(RobotStore.self) private var robot
    @Environment(SettingsStore.self) private var settings
    @State private var timeout = ""
    var body: some View {
        @Bindable var settings = settings
        LabeledContent("언어") {
            Picker("언어", selection: $settings.language) {
                Text(verbatim: "한국어").tag("ko")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "中文").tag("zh-Hans")
            }.pickerStyle(.segmented).labelsHidden()
        }
        LabeledContent("앱 버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        LabeledContent("연결 대상", value: robot.name ?? "—")
        LabeledContent("통신 제한 시간") {
            TextField("초", text: $timeout).dooreField()
            Button("수정") {
                if let value = Int(timeout), (1...3600).contains(value) { settings.timeoutSeconds = value }
            }.buttonStyle(DooreButtonStyle(.primary, small: true)).disabled(Int(timeout).map { !(1...3600).contains($0) } ?? true)
        }.onChange(of: settings.timeoutSeconds, initial: true) { _, value in timeout = String(value) }
        ReportedSlider(title: "시스템 음량", reported: robot.snapshot.volume) { value in
            if let mute = robot.snapshot.soundMute { Task { await robot.setting(.sound(volume: UInt32(value), mute: mute)) } }
        }.disabled(robot.snapshot.soundMute == nil)
        LabeledContent("로그") {
            if let file = robot.aboutLogURL {
                ShareLink(item: file) { Label("로그 공유", systemImage: "square.and.arrow.up") }.buttonStyle(DooreButtonStyle(.line))
            } else { Button("로그 공유") {}.buttonStyle(DooreButtonStyle(.line)).disabled(true) }
        }
        Text("통신 기록을 파일로 내보냅니다.").foregroundStyle(DooreColor.inkSoft)
    }
}
