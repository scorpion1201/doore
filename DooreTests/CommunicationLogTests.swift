import Foundation
import XCTest
@testable import Doore

final class CommunicationLogTests: XCTestCase {
    @MainActor
    func testDailyFilesAppendInOrderAndExposeLatestFileForSharing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let log = CommunicationLog(directory: directory) { timestamp }

        log.record("state connecting")
        log.record("reply woosh.robot.RobotInfo")
        log.record("untrusted\nextra line")
        timestamp.addTimeInterval(86_400)
        log.record("state ready")

        let expectedDay = timestamp.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let latest = directory.appendingPathComponent("\(expectedDay).log")
        let deadline = ContinuousClock.now + .seconds(3)
        while log.url != latest && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(log.url, latest)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        let first = try XCTUnwrap(files.first { $0 != latest })
        let lines = try String(contentsOf: first, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.first?.hasSuffix("state connecting") == true)
        XCTAssertTrue(lines.last?.hasSuffix("reply woosh.robot.RobotInfo") == true)
        XCTAssertTrue(try String(contentsOf: latest, encoding: .utf8).hasSuffix("state ready\n"))
    }
}
