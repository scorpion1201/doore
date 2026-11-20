import Foundation
import SwiftUI

struct ConnectDialog: View {
    @Environment(RobotStore.self) private var robot
    @Environment(SettingsStore.self) private var settings
    @Environment(\.compactLayout) private var compact
    @State private var host = ""
    @State private var port = ""
    @State private var dispatch = false
    @State private var didPrefill = false
    @State private var attempted = false
    @State private var deleting: ConnectionRecord?
    let close: () -> Void

    var body: some View {
        Group {
            if let deleting { confirmRemoval(deleting) }
            else { form }
        }
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            host = robot.host ?? settings.history.first?.host ?? ""
            if let initialPort = robot.port ?? settings.history.first?.port, initialPort != 5480 {
                port = String(initialPort)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DooreSize.compactGap) {
            Text("로봇과 관제 연결").dooreFont(DooreSize.dialogFont, weight: .medium)
                .frame(maxWidth: .infinity)
            HStack(spacing: DooreSize.compactGap) {
                Text("연결 대상")
                radio("로봇", selected: !dispatch) { dispatch = false }
                radio("관제", selected: dispatch) { dispatch = true }
            }
            if dispatch {
                Text("관제 서버 연결은 아직 지원되지 않습니다.").foregroundStyle(DooreColor.inkSoft)
            }
            if compact {
                hostField
                portField
                actionButtons
            } else {
                HStack(spacing: DooreSize.compactPanelPadding) {
                    hostField
                    portField.frame(maxWidth: DooreSize.addressFieldWidth)
                    actionButtons
                }
            }
            if attempted, !validPort || normalizedHost.isEmpty {
                Text("IP와 포트 번호를 확인하세요.").foregroundStyle(DooreColor.danger)
            } else if let message = robot.errorMessage {
                RobotErrorText(message: message).foregroundStyle(DooreColor.danger).textSelection(.enabled)
            }
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DooreSize.compactGap) { statusDetails }.fixedSize()
                    VStack(alignment: .leading, spacing: DooreSize.smallGap) { statusDetails }
                }
            }
            Divider()
            Text("연결 이력").fontWeight(.medium)
            if settings.history.isEmpty {
                Text("연결 이력이 없습니다.").foregroundStyle(DooreColor.inkSoft)
            } else {
                ForEach(settings.history) { record in historyRow(record) }
            }
            Button("닫기", action: close).buttonStyle(DooreButtonStyle(.primary, fullWidth: true))
        }
        .onChange(of: robot.state) { _, state in
            if attempted && state == .ready { close() }
        }
    }

    @ViewBuilder private var statusDetails: some View {
        StatusAddress()
        IndicatorStrip()
        StatusClock()
    }

    private var hostField: some View {
        TextField("IP", text: $host)
            .dooreField()
            #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .accessibilityLabel("IP")
    }

    private var portField: some View {
        TextField("5480 (비워도 됨)", text: $port)
            .dooreField()
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .accessibilityLabel("포트")
    }

    private var normalizedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var portNumber: Int? { port.isEmpty ? 5480 : Int(port) }
    private var validPort: Bool { portNumber.map { (1...65535).contains($0) } ?? false }

    private var actionButtons: some View {
        HStack(spacing: DooreSize.smallGap) {
            Button("연결") {
                attempted = true
                guard !dispatch, !normalizedHost.isEmpty, validPort, let portNumber else { return }
                Task { await robot.connect(host: normalizedHost, port: portNumber) }
            }
            .buttonStyle(DooreButtonStyle(.primary, fullWidth: compact))
            .disabled(dispatch || robot.state == .connecting || robot.state == .syncing)
            Button("끊기") { Task { await robot.disconnect() } }
                .buttonStyle(DooreButtonStyle(.quiet, fullWidth: compact))
                .disabled(robot.state == .disconnected)
        }
    }

    private func radio(_ label: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DooreSize.smallGap) {
                Circle()
                    .strokeBorder(selected ? DooreColor.primary : DooreColor.lineStrong,
                                  lineWidth: selected ? DooreSize.radioRing : DooreSize.outline)
                    .frame(width: DooreSize.radioDiameter, height: DooreSize.radioDiameter)
                Text(label)
            }
            .frame(minHeight: DooreSize.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func confirmRemoval(_ record: ConnectionRecord) -> some View {
        VStack(alignment: .leading, spacing: DooreSize.smallGap) {
            Text("이 연결 이력을 삭제하시겠습니까?")
            Text(verbatim: "\(record.host):\(record.port)").monospacedDigit()
            HStack {
                Button("취소") { deleting = nil }.buttonStyle(DooreButtonStyle(.quiet, small: true))
                Button("확인") {
                    settings.removeConnection(record)
                    deleting = nil
                }.buttonStyle(DooreButtonStyle(.danger, small: true))
            }
        }
    }

    private func historyRow(_ record: ConnectionRecord) -> some View {
        HStack(spacing: DooreSize.smallGap) {
            Button {
                host = record.host
                port = record.port == 5480 ? "" : String(record.port)
                dispatch = false
                attempted = false
            } label: {
                let layout = compact
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DooreSize.tightGap))
                    : AnyLayout(HStackLayout(spacing: DooreSize.compactGap))
                layout {
                    Text(verbatim: "\(record.host):\(record.port)").monospacedDigit()
                    HStack { Text("로봇"); if let name = record.name { Text(verbatim: name) } }
                        .foregroundStyle(DooreColor.inkSoft)
                }
                .frame(maxWidth: .infinity, minHeight: DooreSize.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("삭제") { deleting = record }.buttonStyle(DooreButtonStyle(.danger, small: true))
        }
        .padding(.horizontal, DooreSize.compactGap)
        .padding(.vertical, DooreSize.compactPanelPadding)
        .background(DooreColor.well, in: RoundedRectangle(cornerRadius: DooreSize.rowRadius))
    }
}
