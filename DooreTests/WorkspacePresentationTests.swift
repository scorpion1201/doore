import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class WorkspacePresentationTests: XCTestCase {
    func testKeyboardRoutesFollowTheHomeTileOrder() {
        XCTAssertEqual(WorkspacePage.allCases, [.monitor, .map, .task, .settings, .device, .design])
        XCTAssertEqual(WorkspacePage.allCases.map(\.rawValue), Array(1...6))
    }

    func testDismissingOneWindowDoesNotEnableMotionBehindAnotherDialog() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RobotStore(settings: SettingsStore(defaults: defaults),
                               session: RobotSession(transport: FakeRobotTransport()))
        await store.connect(host: "192.0.2.5", port: 5480)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !store.canTeleoperate, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(store.canTeleoperate)
        let first = UUID(), second = UUID()
        store.setInputBlocked(true, window: first)
        store.setInputBlocked(true, window: second)
        store.setInputBlocked(false, window: first)
        XCTAssertFalse(store.canTeleoperate)
        store.setInputBlocked(false, window: second)
        XCTAssertTrue(store.canTeleoperate)
        await store.disconnect()
    }

    func testAllThreeLocalizationsAreBundled() throws {
        let appBundle = Bundle(for: RobotStore.self)
        for (language, expected) in [("ko", "미연결"), ("en", "Ununited"), ("zh-Hans", "未连接")] {
            let path = try XCTUnwrap(appBundle.path(forResource: language, ofType: "lproj"))
            let resources = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(resources.localizedString(forKey: "미연결", value: nil, table: nil), expected)
        }
    }
}
