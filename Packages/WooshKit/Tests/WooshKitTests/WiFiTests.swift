import Foundation
import XCTest
import WooshKit
import WooshKitTesting

final class WiFiTests: XCTestCase {
    func testWPAWithAutomaticIPv4UsesPublicAPIInnerJSON() throws {
        let password = UUID().uuidString
        let operation = WiFiOperation.add(ssid: "예시", password: password, hidden: true, connectNow: false)
        let wire = try Woosh_Robot_RobotWiFi(jsonUTF8Data: operation.body)
        XCTAssertEqual(wire.order, .kAdd)
        XCTAssertFalse(wire.isConnectNow)
        let profile = try XCTUnwrap(JSONSerialization.jsonObject(with: wire.content) as? [String: Any])
        XCTAssertEqual(profile["essid"] as? String, "예시")
        XCTAssertEqual(profile["auth_method"] as? String, "wpa-psk")
        XCTAssertEqual(profile["hidden"] as? Bool, true)
        XCTAssertEqual(profile["ip4_settings"] as? [String: String], ["method": "auto"])
        XCTAssertEqual(profile["wifi_security"] as? [String: String], ["psk": password])
        XCTAssertFalse(WiFiOperation.add(ssid: "예시", password: "", hidden: false, connectNow: true).allows(RobotSnapshot()))
    }

    func testSavedProfilesOnlyProjectRecognizedFields() throws {
        let list = Data(#"{"profiles":[{"essid":"예시","auth_method":"wpa-psk","ip4_settings":{"method":"auto"}},{"unknown":1}]}"#.utf8)
        let profiles = WiFiNetworkSummary.reported(in: list)
        XCTAssertEqual(profiles.map(\.ssid), ["예시"])
        XCTAssertEqual(profiles.first?.ipMethod, "auto")
        XCTAssertTrue(WiFiNetworkSummary.reported(in: Data("unknown".utf8)).isEmpty)
    }

    func testHotspotDirectionMustMatchReportedModeAndAnAckDoesNotChangeIt() async throws {
        var info = Woosh_Robot_RobotInfo()
        info.network.wifi.mode = .kClient
        let fake = FakeRobotTransport(snapshots: [RobotFeed.robotInfo.rawValue: try info.jsonUTF8Data()])
        let session = RobotSession(transport: fake)
        try await session.connect(to: Endpoint(host: "192.0.2.1"))
        try await session.perform(.wifi(.list))
        try await session.perform(.wifi(.hotspot(enabled: true)))
        do {
            try await session.perform(.wifi(.hotspot(enabled: false)))
            XCTFail("An acknowledgement does not report the new WiFi mode")
        } catch {
            XCTAssertEqual(error as? SessionError, .modeMismatch)
        }
        let calls = await fake.calls
        let requests = try calls.compactMap { call -> Woosh_Robot_RobotWiFi? in
            guard case .request(Woosh_Robot_RobotWiFi.protoMessageName, let body) = call else { return nil }
            return try Woosh_Robot_RobotWiFi(jsonUTF8Data: body)
        }
        XCTAssertEqual(requests.map(\.order), [.kWiFiList, .kHotspot])
        XCTAssertTrue(requests.last?.enable == true)
    }
}
