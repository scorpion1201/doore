import SwiftUI

@main
@MainActor
struct DooreApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(DooreOrientationDelegate.self) private var orientationDelegate
    #endif
    @Environment(\.scenePhase) private var phase
    @State private var settings: SettingsStore
    @State private var robot: RobotStore

    init() {
        let preferences = SettingsStore()
        _settings = State(initialValue: preferences)
        _robot = State(initialValue: RobotStore(settings: preferences))
    }

    var body: some Scene {
        WindowGroup("Woosh Mobile", for: String.self) { launchRoute in
            WorkspaceWindow(launchRoute: launchRoute.wrappedValue)
                .environment(settings)
                .environment(robot)
                .environment(\.locale, Locale(identifier: settings.language))
                .preferredColorScheme(.light)
                .task { await robot.start() }
                .onChange(of: settings.timeoutSeconds) { _, _ in
                    Task { await robot.updateTimeout() }
                }
        }
        .onChange(of: phase) { _, phase in
            Task { await robot.setActive(phase == .active) }
        }
        #if os(macOS)
        .defaultSize(width: DooreSize.defaultWidth, height: DooreSize.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands { WorkspaceCommands(language: settings.language) }
        #endif
    }
}
