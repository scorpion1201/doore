#if canImport(SwiftUI)
import SwiftUI
import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class ScreenRenderingTests: XCTestCase {
    func testWorkspacesRenderBeforeConnectionAndAfterFakeSync() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let robot = RobotStore(settings: settings, session: RobotSession(transport: FakeRobotTransport()))
        let workspace = SceneEditingWorkspace()
        await robot.start()
        for connected in [false, true] {
            if connected {
                await robot.connect(host: "192.0.2.1", port: 5480)
                for _ in 0..<100 where robot.state != .ready {
                    try await Task.sleep(for: .milliseconds(5))
                }
                XCTAssertEqual(robot.state, .ready)
            }
            let screens = [
                AnyView(HomeScreen(open: { _ in })), AnyView(MonitorScreen()), AnyView(MapScreen()),
                AnyView(TaskScreen()), AnyView(SettingsScreen()), AnyView(DeviceScreen()),
                AnyView(DesignScreen()), AnyView(DesignScreen(initialTab: .deploy)),
                AnyView(DesignScreen(initialTab: .statistics))
            ]
            for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390),
                         CGSize(width: 768, height: 1024), CGSize(width: 1280, height: 800)] {
                for (index, screen) in screens.enumerated() {
                    let compact = size.width < 600 || size.height < 480
                    let content = screen
                        .environment(robot).environment(settings).environment(workspace)
                        .environment(\.compactLayout, compact)
                        .environment(\.locale, Locale(identifier: "ko"))
                        .environment(\.dynamicTypeSize, compact ? .xLarge : .large)
                        .frame(width: size.width, height: size.height)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 0.5
                    XCTAssertNotNil(renderer.cgImage, "Screen \(index), \(size), connected=\(connected)")
                }
            }
        }
        await robot.disconnect()
    }
}
#endif
