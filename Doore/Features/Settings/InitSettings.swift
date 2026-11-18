import SwiftUI
import WooshKit

struct InitSettings: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var selection: String?
    @State private var draft: MapPose?
    @State private var draftMapID: String?
    @State private var presented: ResetAction?
    @State private var heading: Double?
    @State private var canvasID = UUID()

    private enum ResetAction: Int, Identifiable {
        case recorded, qr, pose
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .recorded: return "로봇을 제자리에서 초기화할까요?"
            case .qr: return "QR 코드로 로봇 위치를 초기화할까요?"
            case .pose: return "로봇 위치를 지정할까요?"
            }
        }
    }
    private var allowed: Bool { robot.state == .ready && robot.snapshot.allows(.initializeInPlace) }
    private var reportedPose: MapPose? {
        robot.activeMap?.id == robot.poseMapID ? robot.pose : nil
    }

    var body: some View {
        Text("로봇 아이콘을 길게 눌러 옮기고 다이얼로 방향을 맞춘 뒤 손을 떼면 위치가 정해집니다.")
            .foregroundStyle(DooreColor.danger)
        let layout = compact ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
        layout {
            MapCanvasView(map: robot.activeMap, pose: reportedPose, selected: $selection,
                          onMoveRobot: allowed ? { point in propose(point) } : nil)
                .id(canvasID)
            VStack(spacing: DooreSize.smallGap) {
                Button("로봇 아이콘을 원점으로") {
                    canvasID = UUID()
                    if let origin = robot.activeMap?.origin { propose(origin) }
                }.buttonStyle(DooreButtonStyle(.quiet)).disabled(!allowed || robot.activeMap?.origin == nil)
                Text("로봇이 보이지 않을 때 누릅니다.").foregroundStyle(DooreColor.inkSoft)
                Button("제자리 초기화") { presented = .recorded }
                    .buttonStyle(DooreButtonStyle(.primary)).disabled(!allowed)
                Button("QR 코드 복위") { presented = .qr }
                    .buttonStyle(DooreButtonStyle(.quiet)).disabled(!allowed)
                dial
            }.frame(maxWidth: compact ? .infinity : DooreSize.initColumn)
        }
        .sheet(item: $presented, onDismiss: clearDraft) { action in
            VStack(spacing: DooreSize.gap) {
                Text(action.title).font(.headline)
                if action == .pose, let draft {
                    Text(verbatim: String(format: "X %.2f   Y %.2f", draft.x, draft.y)).monospacedDigit()
                    dial
                }
                HStack {
                    Button("취소") { presented = nil }.buttonStyle(DooreButtonStyle(.quiet))
                    Button("확인") { submit(action) }.buttonStyle(DooreButtonStyle(.primary))
                        .disabled(!allowed)
                }
            }.padding(DooreSize.dialogPadding)
        }
        .onChange(of: robot.activeMap?.id) { _, _ in presented = nil; clearDraft() }
        .onChange(of: allowed) { _, value in if !value { presented = nil; clearDraft() } }
    }

    private var dial: some View {
        let angle = heading ?? draft?.theta ?? reportedPose?.theta ?? 0
        return VStack {
            Text("방향 다이얼")
            GeometryReader { proxy in
                let radius = min(proxy.size.width, proxy.size.height) / 2
                let knob = DooreSize.dialKnob
                let reach = radius - knob / 2
                ZStack {
                    Circle().fill(DooreColor.well)
                    Image(systemName: "arrow.right").foregroundStyle(DooreColor.ink)
                        .rotationEffect(.radians(-angle))
                    Circle().fill(DooreColor.surface)
                        .overlay(Circle().stroke(DooreColor.line))
                        .frame(width: knob, height: knob)
                        .offset(x: cos(angle) * reach, y: -sin(angle) * reach)
                }.contentShape(Circle()).gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in heading = atan2(radius - drag.location.y, drag.location.x - radius) }
                    .onEnded { _ in if presented == nil, let pose = reportedPose { propose(pose) } })
            }.frame(width: DooreSize.directionDial, height: DooreSize.directionDial)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("방향 다이얼")
            .accessibilityValue(Text(verbatim: String(format: "%.2f rad", angle)))
            .accessibilityAdjustableAction { direction in
                heading = angle + (direction == .increment ? .pi / 12 : -.pi / 12)
                if presented == nil, let pose = reportedPose { propose(pose) }
            }
            .disabled(!allowed || (reportedPose == nil && draft == nil))
        }
    }

    private func propose(_ point: MapPose) {
        guard allowed, let map = robot.activeMap else { return }
        draftMapID = map.id
        draft = MapPose(x: point.x, y: point.y, theta: heading ?? reportedPose?.theta ?? 0)
        presented = .pose
    }

    private func submit(_ action: ResetAction) {
        let command: RobotCommand
        switch action {
        case .qr: command = .initializeQR
        case .recorded: command = .initializeInPlace
        case .pose:
            guard let draft, let id = draftMapID, id == robot.activeMap?.id else { return }
            command = .setPose(mapID: id, pose: MapPose(x: draft.x, y: draft.y, theta: heading ?? draft.theta))
        }
        presented = nil
        Task { await robot.initializePosition(command) }
    }

    private func clearDraft() { draft = nil; heading = nil; draftMapID = nil }
}
