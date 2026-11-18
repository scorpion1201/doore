import SwiftUI
import WooshKit

struct WiFiSettings: View {
    @Environment(RobotStore.self) private var robot
    @State private var adding = false
    @State private var switchToHotspot: Bool?
    @State private var networks: [WiFiNetworkSummary] = []
    @State private var selected: String?
    @State private var waiting = false
    @State private var modalID = UUID()

    private var switching: Bool { robot.snapshot.wifiMode == 2 || robot.snapshot.wifiMode == 4 }
    private var hotspotEnabled: Bool { robot.snapshot.wifiMode == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DooreSize.gap) {
            HStack {
                Button(hotspotEnabled ? LocalizedStringKey("WiFi 전환") : LocalizedStringKey("핫스팟 전환")) {
                    switchToHotspot = !hotspotEnabled
                }
                .buttonStyle(DooreButtonStyle(.danger))
                .disabled(!robot.snapshot.allows(.wifi(.hotspot(enabled: !hotspotEnabled))))
                Button("WiFi 추가") { adding = true }.buttonStyle(DooreButtonStyle(.primary))
            }
            .disabled(robot.state != .ready || waiting || switching)

            if let name = robot.snapshot.wifiName, !name.isEmpty {
                LabeledContent("연결된 WiFi", value: name)
            }
            if switching {
                ProgressView(robot.snapshot.wifiMode == 2 ? LocalizedStringKey("핫스팟 전환 중, 잠시 기다리세요.") : LocalizedStringKey("WiFi 전환 중"))
            }
            if robot.state != .ready || networks.isEmpty {
                RobotRegionState(message: "로봇에 연결하면 WiFi 정보가 여기에 표시됩니다.", empty: "저장된 WiFi 목록을 받지 못했습니다.")
            } else {
                ForEach(networks) { network in
                    Button { selected = network.id } label: {
                        HStack {
                            Text(verbatim: network.ssid)
                            Spacer()
                            if selected == network.id { Image(systemName: "checkmark") }
                        }.frame(minHeight: DooreSize.buttonHeight)
                    }.buttonStyle(.plain)
                }
                if let network = networks.first(where: { $0.id == selected }) {
                    LabeledContent("이름", value: network.ssid)
                    LabeledContent("보안", value: network.security ?? "—")
                    LabeledContent("IPv4", value: network.ipMethod ?? "—")
                }
            }
        }
        .task(id: robot.state) {
            if robot.state == .ready { await robot.perform(.wifi(.list)) }
            else { adding = false; switchToHotspot = nil; selected = nil }
        }
        .onChange(of: robot.snapshot.wifiList, initial: true) { _, data in
            networks = WiFiNetworkSummary.reported(in: data)
            if !networks.contains(where: { $0.id == selected }) { selected = nil }
        }
        .onChange(of: adding || switchToHotspot != nil) { _, presented in
            robot.setInputBlocked(presented, window: modalID)
        }
        .onDisappear { robot.setInputBlocked(false, window: modalID) }
        .sheet(isPresented: $adding) { AddWiFiNetwork() }
        .alert("네트워크 모드를 전환할까요?", isPresented: Binding(
            get: { switchToHotspot != nil }, set: { if !$0 { switchToHotspot = nil } }
        ), presenting: switchToHotspot) { enabled in
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) {
                waiting = true
                Task {
                    await robot.perform(.wifi(.hotspot(enabled: enabled)))
                    waiting = false
                }
            }
        }
    }
}

private struct AddWiFiNetwork: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RobotStore.self) private var robot
    @State private var ssid = ""
    @State private var password = ""
    @State private var hidden = false
    @State private var sending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DooreSize.gap) {
                Text("WiFi 추가").font(.title2)
                LabeledContent("이름") { TextField("SSID", text: $ssid).dooreField() }
                LabeledContent("보안") { Text(verbatim: "WPA-PSK") }
                LabeledContent("비밀번호") { SecureField("비밀번호", text: $password).dooreField() }
                LabeledContent("IPv4") { Text("자동") }
                Toggle("숨겨진 네트워크", isOn: $hidden)
                if let error = robot.errorMessage { RobotErrorText(message: error).foregroundStyle(DooreColor.danger) }
                HStack {
                    Button("취소") { dismiss() }.buttonStyle(DooreButtonStyle(.quiet))
                    Spacer()
                    Group {
                        Button("저장만") { add(connectNow: false) }.buttonStyle(DooreButtonStyle(.line))
                        Button("연결") { add(connectNow: true) }.buttonStyle(DooreButtonStyle(.primary))
                    }.disabled(!canSave)
                }
                .disabled(sending)
            }.padding(DooreSize.dialogPadding)
        }
        .onDisappear { password = "" }
    }

    private var canSave: Bool {
        robot.state == .ready && robot.snapshot.allows(.wifi(.add(ssid: ssid, password: password, hidden: hidden, connectNow: false)))
    }

    private func add(connectNow: Bool) {
        let operation = RobotCommand.wifi(.add(ssid: ssid, password: password, hidden: hidden, connectNow: connectNow))
        guard robot.state == .ready, robot.snapshot.allows(operation) else { return }
        sending = true
        Task {
            let accepted = await robot.perform(operation)
            sending = false
            if accepted {
                password = ""
                dismiss()
                await robot.perform(.wifi(.list))
            }
        }
    }
}
