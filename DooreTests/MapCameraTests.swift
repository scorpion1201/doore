import CoreGraphics
import XCTest
import WooshKit
@testable import Doore

final class MapCameraTests: XCTestCase {
    func testFollowCentersEachReportedPoseAfterPanningAndKeepsTheDragOnRelease() throws {
        let data = Data(#"{"name":"Example","maps":[{"id":"1","origin":{"x":-5,"y":-5},"resolution":0.5}]}"#.utf8)
        let map = try XCTUnwrap(try SceneModel(data: data).maps.first)
        let imageSize = CGSize(width: 100, height: 50)
        let size = CGSize(width: 400, height: 300)
        let middle = CGPoint(x: 200, y: 150)
        var camera = MapCamera()
        func view(following pose: MapPose? = nil, pan: CGSize = .zero) -> Viewport {
            Viewport(map: map, imageSize: imageSize, size: size, camera: camera, followedPose: pose, pan: pan)
        }
        let overview = view()
        XCTAssertEqual(overview.rect, CGRect(x: 0, y: 50, width: 400, height: 200))
        XCTAssertNil(overview.pose(.zero))

        camera.zoom = camera.magnified(by: 2)
        camera.pan(by: CGSize(width: 30, height: 60), following: nil)
        let initial = MapPose(x: 8, y: 2)
        let latest = MapPose(x: 11, y: 4)
        XCTAssertEqual(view(following: initial).point(initial), middle)
        XCTAssertEqual(view(following: latest).point(latest), middle)
        let drag = CGSize(width: 80, height: -30)
        let duringDrag = view(following: latest, pan: drag)
        camera.pan(by: drag, following: latest)
        XCTAssertEqual(view().rect, duringDrag.rect)
        XCTAssertEqual(view().point(latest), CGPoint(x: 280, y: 120))

        camera.focus(on: initial)
        XCTAssertEqual(view().point(initial), middle)
        XCTAssertEqual(view().pose(middle), initial)
        XCTAssertEqual(camera.zoom, 2)
    }
}
