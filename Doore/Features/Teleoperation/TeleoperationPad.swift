import SwiftUI
import GameController
import WooshKit

@MainActor
struct TeleoperationPad<Center: View>: View {
    let center: () -> Center

    @Environment(RobotStore.self) private var robot
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var phase
    @Environment(\.compactLayout) private var compact
    @Environment(\.isEnabled) private var enabled
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeWindow
    @FocusState private var focused: Bool
    #endif
    @State private var visible = false
    @State private var input = DriveInput()
    @State private var gestureID = UUID()
    @State private var controller = ControllerCapture()

    init(@ViewBuilder center: @escaping () -> Center) {
        self.center = center
    }

    private var available: Bool {
        guard visible, enabled, phase == .active, robot.canTeleoperate, settings.driveMode == "세로" else { return false }
        #if os(macOS)
        return activeWindow == .key
        #else
        return true
        #endif
    }

    var body: some View {
        VStack(spacing: DooreSize.smallGap) {
            HStack(spacing: DooreSize.smallGap) {
                stick(.forward).id(gestureID).disabled(!available)
                center().frame(maxWidth: .infinity)
                stick(.turn).id(gestureID).disabled(!available)
            }

            if !robot.canTeleoperate || settings.driveMode != "세로" {
                Text(blockedReason).foregroundStyle(DooreColor.inkSoft)
            }
        }
        #if os(macOS)
        .focusable()
        .focused($focused)
        .onKeyPress(phases: [.down, .up, .repeat]) { key in
            guard available, focused, let direction = direction(key.key) else { return .ignored }
            if key.phase == .down {
                guard key.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                change { $0.press(direction) }
            }
            if key.phase == .up { change { $0.release(direction) } }
            return .handled
        }
        .onChange(of: focused) { _, hasFocus in
            if !hasFocus { interrupt() }
            else if available { captureController() }
        }
        #endif
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: input.moving)
        #endif
        .onAppear {
            visible = true
            #if os(macOS)
            focused = true
            #endif
        }
        .onDisappear {
            visible = false
            interrupt()
        }
        .onChange(of: available, initial: true) { _, active in
            interrupt()
            if active { captureController() }
        }
        .onChange(of: settings.linearSpeed) { _, _ in restartInput() }
        .onChange(of: settings.angularSpeed) { _, _ in restartInput() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            if available && !controller.attached { captureController() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { note in
            guard let device = note.object as? GCController, controller.owns(device) else { return }
            restartInput()
        }
    }

    private var blockedReason: LocalizedStringKey {
        if robot.isCharging == true { return "충전 중에는 원격 조종을 할 수 없습니다." }
        if robot.taskStateLabel == "실행 중" { return "원격 조종하려면 먼저 작업을 일시정지하세요." }
        if settings.driveMode != "세로" { return "이 로봇의 가로 주행 지원 여부를 확인할 수 없습니다." }
        return "로봇 상태를 확인한 후 원격 조종할 수 있습니다."
    }

    private func stick(_ axis: DriveInput.Axis) -> some View {
        let diameter = compact ? DooreSize.compactJoystick : DooreSize.joystick
        let epoch = gestureID
        return Joystick(axis: axis, value: axis == .forward ? input.forward : input.turn, update: { ratio in
            guard available, gestureID == epoch else { return }
            #if os(macOS)
            if !focused { focused = true }
            #endif
            change { $0.touch(axis, value: ratio) }
        }, release: {
            if gestureID == epoch { change { $0.release(axis) } }
        })
        .frame(maxWidth: diameter)
        .aspectRatio(1, contentMode: .fit)
    }

    private func change(_ changeInput: (inout DriveInput) -> Void) {
        let before = input.velocity(linearLimit: settings.linearSpeed, angularLimit: settings.angularSpeed)
        changeInput(&input)
        let after = input.velocity(linearLimit: settings.linearSpeed, angularLimit: settings.angularSpeed)
        guard after != before else { return }
        if after == .zero { robot.stopMotion() }
        else if available { robot.move(after) }
    }

    private func interrupt() {
        let wasMoving = input.moving
        controller.detach()
        input.interrupt()
        gestureID = UUID()
        if wasMoving { robot.stopMotion() }
    }

    private func restartInput() {
        interrupt()
        if available { captureController() }
    }

    private func captureController() {
        guard !controller.attached else { return }
        #if os(macOS)
        guard focused else { return }
        #endif
        controller.attach(onTransfer: { interrupt() }) { y, x in
            guard available else { return }
            change { $0.sampleController(forward: y, turn: -x) }
        }
    }

    #if os(macOS)
    private func direction(_ key: KeyEquivalent) -> DriveInput.Key? {
        switch key {
        case .upArrow, "w": return .up
        case .downArrow, "s": return .down
        case .leftArrow, "a": return .left
        case .rightArrow, "d": return .right
        default: return nil
        }
    }
    #endif
}

private struct Joystick: View {
    let axis: DriveInput.Axis
    let value: Double
    let update: (Double) -> Void
    let release: () -> Void
    @GestureState private var pressing = false

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = max(1, (diameter - DooreSize.knob) / 2)
            let forward = axis == .forward
            ZStack {
                Circle().fill(DooreColor.well)
                let layout = forward ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
                layout {
                    Image(systemName: forward ? "chevron.up" : "chevron.left")
                    Spacer()
                    Image(systemName: forward ? "chevron.down" : "chevron.right")
                }
                .foregroundStyle(DooreColor.icon)
                .padding(DooreSize.smallGap)
                Circle().fill(DooreColor.surface)
                    .frame(width: DooreSize.knob, height: DooreSize.knob)
                    .shadow(color: DooreColor.lineStrong.opacity(0.38), radius: DooreSize.knobShadow)
                    .offset(x: forward ? 0 : -value * radius, y: forward ? -value * radius : 0)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($pressing) { _, active, _ in active = true }
                .onChanged { gesture in
                    let coordinate = forward ? gesture.location.y : gesture.location.x
                    update((diameter / 2 - coordinate) / radius)
                }
                .onEnded { _ in release() })
            .onChange(of: pressing) { _, down in if !down { release() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(forward ? Text("전진 · 후진") : Text("회전"))
        }
    }
}

@MainActor
private final class ControllerCapture {
    private weak var device: GCController?
    private var onTransfer: (() -> Void)?
    private var attachment = UUID()
    // GameController exposes one handler per profile. An old window must not remove a new owner's handler.
    private static weak var owner: ControllerCapture?
    var attached: Bool { device != nil && Self.owner === self }
    func owns(_ candidate: GCController) -> Bool { device === candidate && attached }

    func attach(onTransfer: @escaping () -> Void, receive: @escaping @MainActor (Double, Double) -> Void) {
        detach()
        guard let device = GCController.controllers().first(where: { $0.extendedGamepad != nil }),
              let pad = device.extendedGamepad else { return }
        Self.owner?.onTransfer?()
        self.device = device
        self.onTransfer = onTransfer
        Self.owner = self
        let token = attachment
        device.handlerQueue = .main
        receive(Double(pad.leftThumbstick.yAxis.value), Double(pad.rightThumbstick.xAxis.value))
        pad.valueChangedHandler = { [weak self] pad, _ in
            MainActor.assumeIsolated {
                guard let self, self.attached, self.attachment == token else { return }
                receive(Double(pad.leftThumbstick.yAxis.value), Double(pad.rightThumbstick.xAxis.value))
            }
        }
    }

    func detach() {
        attachment = UUID()
        onTransfer = nil
        if Self.owner === self {
            device?.extendedGamepad?.valueChangedHandler = nil
            Self.owner = nil
        }
        device = nil
    }
}
