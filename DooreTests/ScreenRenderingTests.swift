#if canImport(SwiftUI)
import SwiftUI
#if os(iOS)
import UIKit
#endif
import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class ScreenRenderingTests: XCTestCase {
    #if os(iOS)
    func testTallDialogHasAScrollableViewport() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let settings = SettingsStore()
        let robot = RobotStore(settings: settings, session: RobotSession(transport: FakeRobotTransport()))
        let dialog = DialogCard(compact: true, availableHeight: 500) { ConnectDialog(close: {}) }
            .environment(robot).environment(settings)
            .environment(\.compactLayout, true)
            .environment(\.dynamicTypeSize, .accessibility5)
        let host = UIHostingController(rootView: dialog)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()

        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(in: host.view))
        XCTAssertGreaterThan(scroll.bounds.height, 0)
        XCTAssertLessThanOrEqual(scroll.bounds.height, 500)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
    }
    #endif

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
                AnyView(HomeScreen(open: { _ in })), AnyView(MonitorScreen(confirmShortcut: { _ in })), AnyView(MapScreen()),
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
