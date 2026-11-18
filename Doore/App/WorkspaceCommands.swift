import SwiftUI

private struct TaskPauseKey: FocusedValueKey { typealias Value = () -> Void }
private struct TaskResumeKey: FocusedValueKey { typealias Value = () -> Void }
private struct TaskCancelKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var taskPause: (() -> Void)? {
        get { self[TaskPauseKey.self] }
        set { self[TaskPauseKey.self] = newValue }
    }
    var taskResume: (() -> Void)? {
        get { self[TaskResumeKey.self] }
        set { self[TaskResumeKey.self] = newValue }
    }
    var taskCancel: (() -> Void)? {
        get { self[TaskCancelKey.self] }
        set { self[TaskCancelKey.self] = newValue }
    }
}

#if os(macOS)
private struct NavigateKey: FocusedValueKey { typealias Value = (WorkspacePage) -> Void }
private struct ConnectKey: FocusedValueKey { typealias Value = () -> Void }
private struct DisconnectKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var navigateWorkspace: ((WorkspacePage) -> Void)? {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
    var connectRobot: (() -> Void)? {
        get { self[ConnectKey.self] }
        set { self[ConnectKey.self] = newValue }
    }
    var disconnectRobot: (() -> Void)? {
        get { self[DisconnectKey.self] }
        set { self[DisconnectKey.self] = newValue }
    }
}

struct WorkspaceCommands: Commands {
    let language: String

    // Commands are rendered in the system menu bar, outside the window's locale environment.
    private func title(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.navigateWorkspace) private var navigate
    @FocusedValue(\.connectRobot) private var connect
    @FocusedValue(\.disconnectRobot) private var disconnect
    @FocusedValue(\.taskPause) private var pause
    @FocusedValue(\.taskResume) private var resume
    @FocusedValue(\.taskCancel) private var cancel
    @FocusedValue(\.designUndo) private var undo
    @FocusedValue(\.designRedo) private var redo
    @FocusedValue(\.designSave) private var save
    @FocusedValue(\.designLayers) private var layers

    var body: some Commands {
        CommandMenu(title("로봇")) {
            Button(title("연결")) { connect?() }.keyboardShortcut("k").disabled(connect == nil)
            Button(title("끊기")) { disconnect?() }.disabled(disconnect == nil)
        }
        CommandMenu(title("보기")) {
            ForEach(WorkspacePage.allCases) { page in
                Button(title(page.title)) { navigate?(page) }
                    .keyboardShortcut(KeyEquivalent(Character(String(page.rawValue))))
                    .disabled(navigate == nil)
            }
            Divider()
            Menu(title("레이어")) {
                ForEach(["자", "주행 금지", "교통 통제", "구역", "스테이션", "경로", "로봇"], id: \.self) { layer in
                    Toggle(title(layer), isOn: Binding(get: {
                        layers?.wrappedValue.contains(layer) == true
                    }, set: { enabled in
                        guard let layers else { return }
                        if enabled { layers.wrappedValue.insert(layer) }
                        else { layers.wrappedValue.remove(layer) }
                    }))
                }
            }.disabled(layers == nil)
            Divider()
            Button(title("새 창에서 모니터 열기")) { openWindow(value: "design-monitor") }
            Button(title("새 창에서 배치 열기")) { openWindow(value: "deploy") }
        }
        CommandMenu(title("작업")) {
            Button(title("일시정지")) { pause?() }.disabled(pause == nil)
            Button(title("계속")) { resume?() }.disabled(resume == nil)
            Button(title("취소")) { cancel?() }.disabled(cancel == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(title("실행 취소")) { undo?() }.keyboardShortcut("z").disabled(undo == nil)
            Button(title("다시 실행")) { redo?() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(redo == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button(title("저장")) { save?() }.keyboardShortcut("s").disabled(save == nil)
        }
    }
}
#endif
