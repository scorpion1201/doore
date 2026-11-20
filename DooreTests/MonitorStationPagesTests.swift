import XCTest
@testable import Doore

final class MonitorStationPagesTests: XCTestCase {
    func testPagingIncludesEachStationOnceAndKeepsTheFinalPartialPage() {
        let pages = MonitorStationPages(count: 12, width: 816)
        XCTAssertEqual(pages.pageCount, 3)
        XCTAssertEqual(pages.indices(on: 0), 0..<5)
        XCTAssertEqual(pages.indices(on: 1), 5..<10)
        XCTAssertEqual(pages.indices(on: 2), 10..<12)
        XCTAssertEqual(pages.chipWidth, DooreSize.stationMaxWidth)
    }

    func testCompactLayoutReflowsWithoutDroppingStations() {
        let pages = MonitorStationPages(count: 7, width: 334, compactLabelWidth: 21)
        XCTAssertEqual(pages.perPage, 5)
        XCTAssertEqual(pages.indices(on: 1), 5..<7)
        XCTAssertGreaterThanOrEqual(pages.chipWidth, DooreSize.tapTarget)
        XCTAssertLessThanOrEqual(pages.chipWidth, DooreSize.stationMaxWidth)
        XCTAssertEqual(MonitorStationPages(count: 0, width: 334).pageCount, 0)
    }

    func testWiderLabelsGetEnoughRoomOnPhone() {
        let pages = MonitorStationPages(count: 7, width: 334, compactLabelWidth: 93)
        XCTAssertEqual(pages.perPage, 2)
        XCTAssertGreaterThan(pages.chipWidth, 93)
        XCTAssertEqual(pages.indices(on: 3), 6..<7)
    }
}
