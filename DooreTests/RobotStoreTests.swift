import XCTest
import WooshKit
import WooshKitTesting
@testable import Doore

@MainActor
final class RobotStoreTests: XCTestCase {
    func testHistoryPersistsOnlyOnSuccessfulSyncAndDisconnectClearsLiveData() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.language, "ko")
        let fake = FakeRobotTransport()
        let store = RobotStore(settings: settings, session: RobotSession(transport: fake))
        await store.start()
        await fake.enqueue(.rejected("busy"), for: RobotFeed.robotInfo.rawValue)
        await store.connect(host: "192.0.2.9", port: 5480)
        XCTAssertEqual(store.errorMessage, "busy")
        XCTAssertFalse(store.errorMessageIsLocal)
        XCTAssertTrue(settings.history.isEmpty)
        await store.retry()
        try await wait { store.state == .ready && !settings.history.isEmpty }
        XCTAssertEqual(store.battery, 82)
        let settingsAgain = SettingsStore(defaults: defaults)
        XCTAssertEqual(settingsAgain.history.first?.host, "192.0.2.9")
        await store.disconnect()
        try await wait { store.state == .disconnected }
        XCTAssertNil(store.battery)
        XCTAssertNil(store.scene)
    }

    func testInvalidAddressAndUnreportedModeProduceNoCommand() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeRobotTransport(snapshots: [:])
        let store = RobotStore(settings: SettingsStore(defaults: defaults), session: RobotSession(transport: fake))
        await store.connect(host: "bad/address", port: 5480)
        let initial = await fake.calls
        XCTAssertTrue(initial.isEmpty)
        await store.connect(host: "192.0.2.2", port: 5480)
        try await wait { store.state == .ready }
        let before = await fake.calls
        await store.controlTask(.resume)
        await store.buildMap(.add, name: "example")
        let after = await fake.calls
        XCTAssertEqual(before, after)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Store did not receive the expected session event")
    }
}
