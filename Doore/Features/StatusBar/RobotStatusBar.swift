import SwiftUI

struct RobotStatusBar: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    let home: () -> Void
    let showStatus: () -> Void

    var body: some View {
        let height = compact ? DooreSize.compactStatusHeight : DooreSize.statusHeight
        HStack(spacing: compact ? DooreSize.smallGap : DooreSize.gap) {
            Button(action: home) {
                Image(systemName: "house")
                    .font(.system(size: compact ? DooreSize.compactHomeIcon : DooreSize.homeIcon))
                    .foregroundStyle(DooreColor.primaryInk)
                    .frame(width: height, height: height)
                    .background(DooreColor.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("홈")
            .accessibilityIdentifier("status.home")
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                items.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) { items }.scrollIndicators(.hidden)
            }
            .padding(.horizontal, compact ? DooreSize.smallGap : DooreSize.panelPadding)
            .frame(minHeight: height)
            .background(DooreColor.surface, in: UnevenRoundedRectangle(
                topLeadingRadius: height / 2, bottomLeadingRadius: height / 2))
        }
        .dooreFont(compact ? DooreSize.smallFont : DooreSize.statusFont)
        .padding(.leading, compact ? DooreSize.compactGap : DooreSize.gap)
        .padding(.top, compact ? DooreSize.smallGap : DooreSize.gap)
    }

    private var items: some View {
        HStack(spacing: compact ? DooreSize.smallGap : DooreSize.gap) {
            Button {
                robot.showConnect = true
            } label: {
                capsule(outline: ready ? DooreColor.primary : DooreColor.lineStrong) {
                    HStack(spacing: DooreSize.tightGap) {
                        Image(systemName: "sensor.tag.radiowaves.forward")
                            .foregroundStyle(ready ? DooreColor.primary : DooreColor.icon)
                        if ready, let name = robot.name {
                            Text(verbatim: name).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: DooreSize.addressFieldWidth)
                        } else {
                            Text(connectionLabel)
                        }
                    }
                }
            }
            .accessibilityIdentifier("status.connection")
            Button(action: showStatus) {
                capsule(outline: stateOutline, width: warning || fault ? DooreSize.outline * 2 : DooreSize.outline) {
                    Text(stateText)
                        .foregroundStyle(fault ? DooreColor.danger : (ready ? DooreColor.ink : DooreColor.inkSoft))
                }
            }
            .accessibilityIdentifier("status.state")
            if !compact {
                divider
                StatusAddress()
            }
            HStack(spacing: DooreSize.tightGap) {
                Image(systemName: batterySymbol)
                    .foregroundStyle(robot.isCharging == true && ready ? DooreColor.good : DooreColor.inkSoft)
                if ready, let charge = robot.battery {
                    Text(charge, format: .percent.scale(1)).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("배터리")
            .accessibilityValue(batteryDescription)
            if !compact {
                divider
                IndicatorStrip()
                divider
                StatusClock()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(ready ? DooreColor.ink : DooreColor.inkSoft)
    }

    private var batteryDescription: Text {
        if ready, let charge = robot.battery { return Text(charge, format: .percent.scale(1)) }
        return Text("정보 없음")
    }

    private var ready: Bool { robot.state == .ready }
    private var warning: Bool { ready && robot.stateLabel == "경고" }
    private var fault: Bool { ready && robot.stateLabel == "고장" }
    private var connectionLabel: LocalizedStringKey {
        switch robot.state {
        case .connecting: "연결 중"
        case .syncing: "동기화 중"
        case .ready: "로봇"
        case .disconnected, .reconnecting: "미연결"
        }
    }
    private var stateText: LocalizedStringKey {
        ready ? LocalizedStringKey(robot.stateLabel ?? "정보 없음") : "오프라인"
    }
    private var stateOutline: Color {
        if fault { return DooreColor.danger }
        if warning { return DooreColor.warn }
        return ready ? DooreColor.primary : DooreColor.lineStrong
    }
    private var batterySymbol: String {
        if ready, robot.isCharging == true { return "battery.100.bolt" }
        guard ready, let charge = robot.battery else { return "battery.0" }
        switch charge {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var divider: some View {
        Rectangle().fill(DooreColor.line).frame(width: DooreSize.hairline, height: DooreSize.separatorHeight)
            .accessibilityHidden(true)
    }

    private func capsule<Content: View>(outline: Color, width: CGFloat = DooreSize.outline,
                                        @ViewBuilder content: () -> Content) -> some View {
        content().padding(.vertical, DooreSize.tightGap)
            .padding(.horizontal, compact ? DooreSize.smallGap : DooreSize.compactGap)
            .overlay { Capsule().strokeBorder(outline, lineWidth: width) }
            .frame(minWidth: DooreSize.tapTarget, minHeight: DooreSize.tapTarget)
            .contentShape(Rectangle())
    }
}

struct StatusAddress: View {
    @Environment(RobotStore.self) private var robot

    var body: some View {
        if robot.state == .ready, let address = robot.snapshot.robotIP ?? robot.host {
            HStack(spacing: DooreSize.smallGap) { Text("IP"); Text(verbatim: address).monospacedDigit() }
                .accessibilityElement(children: .combine)
        } else {
            Text("IP 없음")
        }
    }
}

struct StatusClock: View {
    var body: some View {
        TimelineView(.everyMinute) { tick in
            Text(tick.date, style: .time).monospacedDigit()
        }
    }
}

struct IndicatorStrip: View {
    @Environment(RobotStore.self) private var robot

    var body: some View {
        HStack(spacing: DooreSize.compactGap) {
            indicator("wifi", label: "WiFi", value: robot.hasWiFi)
            indicator("server.rack", label: "관제 연결", value: robot.hasDispatchConnection)
            indicator("light.beacon.max", label: "비상 정지", value: robot.isEmergencyStopped, color: DooreColor.danger)
            indicator("location", label: "위치 확인", value: robot.isPositionConfirmed)
        }
    }

    private func indicator(_ symbol: String, label: LocalizedStringKey, value: Bool?,
                           color: Color = DooreColor.ink) -> some View {
        let state = robot.state == .ready ? value : nil
        return Image(systemName: symbol)
            .foregroundStyle(state == true ? color : DooreColor.lineStrong)
            .symbolVariant(state == true ? .fill : .none)
            .accessibilityLabel(Text(label))
            .accessibilityValue(state == nil ? Text("정보 없음") : (state == true ? Text("켜짐") : Text("꺼짐")))
    }
}

struct RobotStatusDialog: View {
    @Environment(RobotStore.self) private var robot
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DooreSize.compactGap) {
            Text("상태 코드").dooreFont(DooreSize.dialogFont, weight: .medium)
                .frame(maxWidth: .infinity)
            if robot.state == .ready {
                LabeledContent("로봇 상태") { Text(LocalizedStringKey(robot.stateLabel ?? "정보 없음")) }
                LabeledContent("동작 종류") {
                    if let action = robot.actionLabel {
                        Text(LocalizedStringKey(action == "대기" ? "action.wait" : action))
                    } else { Text(verbatim: "—") }
                }
                LabeledContent("상태 코드") { Text(verbatim: robot.statusCode ?? "—") }
                if let message = robot.statusMessage { Text(verbatim: message).textSelection(.enabled) }
            } else {
                RobotRegionState(message: "로봇에 연결하면 상태 코드가 여기에 표시됩니다.")
            }
            Button("닫기", action: close).buttonStyle(DooreButtonStyle(.primary, fullWidth: true))
        }
    }
}
