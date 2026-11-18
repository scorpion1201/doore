import Foundation
import XCTest
@testable import WooshKit

final class SceneModelTests: XCTestCase {
    func testObservedMapRoundTripAcrossBottomLeftOrigin() throws {
        let data = Data(#"{"name":"Example","maps":[{"id":"12","name":"floor","origin":{"x":-5,"y":-5},"resolution":0.05,"markInfo":{"storages":[{"identity":{"no":"A1"},"pose":{"real":{"x":2,"y":3}}}]}}]}"#.utf8)
        let scene = try SceneModel(data: data)
        let map = try XCTUnwrap(scene.map(id: "12"))
        let point = try XCTUnwrap(map.stations.first?.pose)
        let pixel = try XCTUnwrap(map.pixel(for: point, height: 400))
        XCTAssertEqual(pixel.x, 140, accuracy: 1e-5)
        XCTAssertEqual(pixel.y, 240, accuracy: 1e-5)
        XCTAssertEqual(map.world(xPixel: pixel.x, yPixel: pixel.y, height: 400), point)
        XCTAssertNil(scene.map(id: "missing"))
    }

    func testAbsentAndZeroPosesAreDistinct() {
        XCTAssertNil(MapPose(data: Data("{}".utf8)))
        XCTAssertEqual(MapPose(data: Data(#"{"pose":{}}"#.utf8)), MapPose(x: 0, y: 0))
        XCTAssertNil(MapPose(data: Data(#"{"pose":{"x":"NaN"}}"#.utf8)))
    }

    func testInvalidGeometryDoesNotGenerateLocations() throws {
        let scene = try SceneModel(data: Data(#"{"name":"Example","maps":[{"id":1,"name":"F1","resolution":0}]}"#.utf8))
        XCTAssertNil(scene.map(id: "1")?.pixel(for: MapPose(x: 0, y: 0), height: 400))
        XCTAssertNil(scene.map(id: nil))
    }
}
