import SwiftUI
import WooshKit

/// Lets the user recover at the place where robot data was expected.
struct RobotRegionState: View {
    let message: LocalizedStringKey
    var empty: LocalizedStringKey = "표시할 항목이 없습니다."
    @Environment(RobotStore.self) private var robot

    var body: some View {
        VStack(spacing: DooreSize.smallGap) {
            switch robot.state {
            case .connecting, .syncing:
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DooreSize.tightGap)
                        .fill(DooreColor.well)
                        .frame(height: DooreSize.buttonHeight)
                }
                .accessibilityHidden(true)
                ProgressView("불러오는 중")
            case .reconnecting:
                Text("로봇과의 연결이 끊겼습니다. 다시 연결하는 중입니다.").foregroundStyle(DooreColor.danger)
                retry("다시 연결")
            case .disconnected:
                if let error = robot.errorMessage {
                    RobotErrorText(message: error).foregroundStyle(DooreColor.danger)
                    retry("다시 시도")
                } else {
                    Text(message)
                    Button("로봇 연결") { robot.showConnect = true }.buttonStyle(DooreButtonStyle(.primary))
                }
            case .ready:
                if let error = robot.errorMessage {
                    RobotErrorText(message: error).foregroundStyle(DooreColor.danger)
                    retry("다시 시도")
                } else { Text(empty) }
            }
        }
        .multilineTextAlignment(.center)
        .padding(DooreSize.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retry(_ label: LocalizedStringKey) -> some View {
        Button(label) { Task { await robot.retry() } }.buttonStyle(DooreButtonStyle(.line))
    }
}

struct ModeBanner: View {
    let requiredWork: String
    let mode: Int
    @Environment(RobotStore.self) private var robot

    var body: some View {
        if robot.state == .ready && (robot.workModeLabel != requiredWork || robot.controlModeLabel != "자동") {
            ViewThatFits(in: .horizontal) {
                HStack { content }
                VStack { content }
            }
            .padding(DooreSize.smallGap)
            .frame(maxWidth: .infinity)
            .background(DooreColor.primaryTint, in: RoundedRectangle(cornerRadius: DooreSize.smallGap))
        }
    }

    @ViewBuilder private var content: some View {
        Text(mode == 1 ? LocalizedStringKey("지도를 작성하려면 자동 모드의 배치 모드여야 합니다.")
                       : LocalizedStringKey("작업을 보내려면 자동 모드의 작업 모드여야 합니다."))
        if robot.workModeLabel != requiredWork {
            Button(mode == 1 ? LocalizedStringKey("배치 모드로 전환") : LocalizedStringKey("작업 모드로 전환")) {
                Task { await robot.switchWorkMode(mode) }
            }.buttonStyle(DooreButtonStyle(.primary))
        }
    }
}

struct OperateMapHeader: View {
    let map: MapModel?
    @Binding var follow: Bool
    @Environment(RobotStore.self) private var robot
    var body: some View {
        HStack {
            ScrollView(.horizontal) {
                HStack(spacing: DooreSize.smallGap) {
                    if let name = robot.scene?.name, let map { Text(verbatim: "\(name):\(map.name)") }
                    if let destination = robot.taskDestination { Text("목적지"); Text(verbatim: destination) }
                    if let kind = robot.taskTypeLabel { Text(LocalizedStringKey(kind)) }
                    if let action = robot.actionLabel { Text(LocalizedStringKey(action == "대기" ? "action.wait" : action)) }
                    if let progress = robot.taskStateLabel {
                        Text(LocalizedStringKey(progress))
                            .foregroundStyle(progress == "일시정지" ? DooreColor.danger : DooreColor.primary)
                    }
                    if let point = robot.pose, robot.poseMapID == map?.id, map != nil {
                        Text(verbatim: String(format: "(%.2f, %.2f)", point.x, point.y)).monospacedDigit()
                    }
                }
            }
            Button { follow.toggle() } label: {
                Image(systemName: follow ? "location.fill" : "location").frame(minWidth: DooreSize.tapTarget, minHeight: DooreSize.tapTarget)
            }.accessibilityLabel("로봇 따라가기").accessibilityValue(follow ? Text("켜짐") : Text("꺼짐"))
                .buttonStyle(.plain).disabled(robot.pose == nil || robot.poseMapID != map?.id)
        }
    }
}
