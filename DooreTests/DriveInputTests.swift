import XCTest
import WooshKit
@testable import Doore

final class DriveInputTests: XCTestCase {
    func testTouchAxesCombineClampAndStopUntilBothSticksAreReleased() {
        var input = DriveInput()
        input.touch(.forward, value: 0.5)
        input.touch(.turn, value: -2)
        XCTAssertEqual(input.velocity(linearLimit: 0.2, angularLimit: 0.3), RobotVelocity(linear: 0.1, angular: -0.3))
        input.release(.forward)
        input.touch(.turn, value: 0.5)
        XCTAssertFalse(input.moving)
        input.release(.turn)
        input.touch(.turn, value: 0.5)
        XCTAssertTrue(input.moving)
    }

    func testControllerRequiresNeutralAfterOpeningInterruptingAndReleasing() {
        var input = DriveInput()
        input.sampleController(forward: 1, turn: 0)
        XCTAssertFalse(input.moving)
        input.sampleController(forward: 0.02, turn: 0)
        input.sampleController(forward: 1, turn: 0.5)
        XCTAssertTrue(input.moving)
        input.sampleController(forward: 1, turn: 0)
        input.sampleController(forward: 0.9, turn: 0)
        XCTAssertFalse(input.moving)
        input.sampleController(forward: 0, turn: 0)
        input.sampleController(forward: 0.5, turn: 0)
        XCTAssertTrue(input.moving)
        input.interrupt()
        input.sampleController(forward: 0.5, turn: 0)
        XCTAssertFalse(input.moving)
    }

    func testHeldKeysAndOtherDevicesDoNotRestartMotionAfterRelease() {
        var input = DriveInput()
        input.sampleController(forward: 0, turn: 0)
        input.press(.up)
        input.press(.left)
        input.sampleController(forward: -1, turn: 0)
        XCTAssertEqual(input.forward, 1)
        XCTAssertEqual(input.turn, 1)
        input.release(.left)
        input.press(.up)
        input.sampleController(forward: -1, turn: 0)
        XCTAssertFalse(input.moving)
        input.release(.up)
        input.press(.down)
        XCTAssertEqual(input.forward, -1)
        XCTAssertEqual(input.velocity(linearLimit: .infinity, angularLimit: 0.3), .zero)
    }
}
