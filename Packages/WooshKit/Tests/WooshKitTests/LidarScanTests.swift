import XCTest
import WooshKit

final class LidarScanTests: XCTestCase {
    func testSensorRangeBoundsAndProtobufSpecialValues() throws {
        let data = Data(#"{"rangeMin":0.1,"rangeMax":3,"ranges":[0,0.05,0.1,2,3,4,"NaN","Infinity"],"future":true}"#.utf8)
        let scan = try LidarScan(data: data)
        XCTAssertEqual(scan.samples, 8)
        XCTAssertEqual(scan.validSamples, 3)
        XCTAssertEqual(scan.nearest, 0.1)
        XCTAssertEqual(scan.farthest, 3)
    }

    func testEmptyScanAndMalformedMessage() throws {
        let scan = try LidarScan(data: Data("{}".utf8))
        XCTAssertEqual(scan.validSamples, 0)
        XCTAssertNil(scan.nearest)
        XCTAssertNil(scan.farthest)
        XCTAssertThrowsError(try LidarScan(data: Data(#"{"ranges":false}"#.utf8)))
    }

    func testMapFrameReportsOpaquePayloadWithoutAssumingAnEncoding() throws {
        let frame = try MapBuildFrame(data: Data(#"{"width":200,"height":300,"mapData":"AAEC"}"#.utf8))
        XCTAssertEqual(frame.width, 200)
        XCTAssertEqual(frame.height, 300)
        XCTAssertEqual(frame.payloadBytes, 3)
    }
}
