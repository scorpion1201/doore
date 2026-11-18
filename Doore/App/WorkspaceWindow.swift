import SwiftUI

private enum WorkspaceDialog { case connection, status }

@MainActor
struct WorkspaceWindow: View {
    @Environment(RobotStore.self) private var robot
    @State private var windowID = UUID()
    @State private var page: WorkspacePage?
    @State private var dialog: WorkspaceDialog?
    @State private var sceneWorkspace = SceneEditingWorkspace()
    @State private var openDeploy: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var widthClass
    #elseif os(macOS)
    @Environment(\.controlActiveState) private var activeState
    #endif

    init(launchRoute: String?) {
        _page = State(initialValue: launchRoute == "deploy" || launchRoute == "design-monitor" ? .design : nil)
        _openDeploy = State(initialValue: launchRoute == "deploy")
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = compactLayout(at: geometry.size)
            ZStack {
                DooreColor.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    RobotStatusBar(home: { navigate(nil) }, showStatus: { present(.status) })
                    if let message = robot.errorMessage, robot.state == .ready {
                        HStack(spacing: DooreSize.compactGap) {
                            RobotErrorText(message: message).foregroundStyle(DooreColor.danger)
                            Spacer()
                            Button("닫기") { robot.errorMessage = nil }
                                .buttonStyle(DooreButtonStyle(.quiet, small: true))
                        }
                        .padding(.horizontal, compact ? DooreSize.compactGap : DooreSize.gap)
                    }
                    if let page {
                        screen(page)
                            .padding(compact ? DooreSize.compactGap : DooreSize.gap)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        HomeScreen(open: { navigate($0) })
                    }
                }
                .accessibilityHidden(dialog != nil)
                .disabled(dialog != nil)
                if let dialog {
                    modal(compact: compact, height: geometry.size.height, dismiss: { present(nil) }) {
                        switch dialog {
                        case .connection: ConnectDialog { present(nil) }
                        case .status: RobotStatusDialog(connect: { present(.connection) }, close: { present(nil) })
                        }
                    }
                }
            }
            .environment(\.compactLayout, compact)
            .dooreFont(compact ? DooreSize.smallFont : DooreSize.bodyFont)
        }
        .environment(sceneWorkspace)
        .foregroundStyle(DooreColor.ink)
        .tint(DooreColor.primary)
        .onChange(of: robot.showConnect) { _, requested in
            guard requested else { return }
            #if os(macOS)
            guard activeState == .key else { return }
            #endif
            present(.connection)
            robot.showConnect = false
        }
        .onDisappear { robot.setInputBlocked(false, window: windowID) }
        #if os(macOS)
        .frame(minWidth: DooreSize.defaultWidth, minHeight: DooreSize.defaultHeight)
        .focusedSceneValue(\.navigateWorkspace, { navigate($0) })
        .focusedSceneValue(\.connectRobot, { present(.connection) })
        .focusedSceneValue(\.disconnectRobot, robot.state == .disconnected ? nil : { Task { await robot.disconnect() } })
        #endif
    }

    private func compactLayout(at size: CGSize) -> Bool {
        #if os(iOS)
        widthClass == .compact || (size.height < DooreSize.compactLandscapeHeight && size.width > size.height)
        #else
        false
        #endif
    }

    private func present(_ next: WorkspaceDialog?) {
        guard dialog != next else { return }
        robot.setInputBlocked(next != nil, window: windowID)
        dialog = next
    }

    private func navigate(_ to: WorkspacePage?) {
        robot.stopMotion()
        present(nil)
        openDeploy = false
        page = to
    }

    @ViewBuilder private func screen(_ page: WorkspacePage) -> some View {
        switch page {
        case .monitor: MonitorScreen()
        case .map: MapScreen()
        case .task: TaskScreen()
        case .settings: SettingsScreen()
        case .device: DeviceScreen()
        case .design: DesignScreen(initialTab: openDeploy ? .deploy : .monitor)
        }
    }

    private func modal<Content: View>(compact: Bool, height: CGFloat, dismiss: @escaping () -> Void,
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
        ZStack {
            DooreColor.scrim.ignoresSafeArea()
            DialogCard(compact: compact, availableHeight: height, content: content)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, dismiss)
                #if os(macOS)
                .onExitCommand(perform: dismiss)
                #endif
        }
    }
}

private struct DialogHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct DialogCard<Content: View>: View {
    let compact: Bool
    let availableHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat?

    var body: some View {
        let inset = compact ? DooreSize.compactGap : DooreSize.gap
        let maxHeight = max(DooreSize.buttonHeight, availableHeight - inset * 2)
        ScrollView {
            content()
                .padding(compact ? DooreSize.compactGap : DooreSize.dialogPadding)
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DialogHeightKey.self, value: geometry.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(measuredHeight ?? maxHeight, maxHeight))
        .frame(maxWidth: DooreSize.dialogWidth)
        .background(DooreColor.surface, in: RoundedRectangle(cornerRadius: DooreSize.radius))
        .clipShape(RoundedRectangle(cornerRadius: DooreSize.radius))
        .padding(inset)
        .onPreferenceChange(DialogHeightKey.self) { measuredHeight = $0 }
    }
}

struct RobotErrorText: View {
    @Environment(RobotStore.self) private var robot
    let message: String

    var body: some View {
        if robot.errorMessageIsLocal { Text(LocalizedStringKey(message)) }
        else { Text(verbatim: message) }
    }
}
