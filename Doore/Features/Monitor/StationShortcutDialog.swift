import SwiftUI
import WooshKit

struct StationShortcutDialog: View {
    let pending: RobotStore.PendingStationShortcut
    let dismiss: () -> Void
    @Environment(RobotStore.self) private var robot
    @State private var failure: RobotRequestFailure?
    @State private var presentationID = UUID()

    var body: some View {
        VStack(spacing: DooreSize.gap) {
            switch pending.shortcut {
            case .charge: Text("충전하러 갈까요?")
            case .park: Text("주차하러 갈까요?")
            }
            LabeledContent("목적지") {
                if let station = pending.shortcut.station { Text(verbatim: station) }
                else { Text("자동") }
            }
            ModeBanner(requiredWork: "작업", mode: 2)
            if let failure { TaskSendError(failure: failure) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DooreSize.smallGap) { actions }
                VStack(spacing: DooreSize.smallGap) { actions }
            }
        }
        .onChange(of: robot.state) { _, state in if state != .ready { dismiss() } }
        .onDisappear { presentationID = UUID() }
    }

    @ViewBuilder private var actions: some View {
        if case .charge = pending.shortcut {
            Button("수동 충전") {}.buttonStyle(DooreButtonStyle(.danger)).disabled(true)
                .help("수동 충전 명령은 로봇 모델별 확인이 필요합니다.")
                .accessibilityHint("수동 충전 명령은 로봇 모델별 확인이 필요합니다.")
        }
        Button("취소", action: dismiss).buttonStyle(DooreButtonStyle(.quiet))
        Button("확인") {
            let id = presentationID
            failure = nil
            Task {
                guard let reply = await robot.sendShortcut(pending) else { return }
                taskFeedback(reply)
                guard presentationID == id else { return }
                switch reply {
                case .success: dismiss()
                case .failure(let reason): failure = reason
                }
            }
        }
        .buttonStyle(DooreButtonStyle(.primary))
        .disabled(!robot.canSendShortcut(pending))
    }
}
