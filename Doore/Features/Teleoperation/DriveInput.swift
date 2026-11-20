import WooshKit

/// Deflection from a single input device. Releasing one held control stops both axes.
struct DriveInput {
    enum Axis: Hashable { case forward, turn }
    enum Key: Hashable { case up, down, left, right }
    private enum Source { case touch, keyboard, controller }

    private var source: Source?
    private var touches: Set<Axis> = []
    private var keys: Set<Key> = []
    private var controllerArmed = false
    private(set) var forward = 0.0
    private(set) var turn = 0.0
    var moving: Bool { forward != 0 || turn != 0 }

    private mutating func stop() {
        if source == .controller { controllerArmed = false }
        source = nil
        forward = 0
        turn = 0
    }

    mutating func interrupt() {
        self = DriveInput()
    }

    mutating func touch(_ axis: Axis, value: Double) {
        let starting = touches.isEmpty
        touches.insert(axis)
        if source == nil && starting { source = .touch }
        guard source == .touch else { return }
        let ratio = value.isFinite ? min(1, max(-1, value)) : 0
        if axis == .forward { forward = ratio } else { turn = ratio }
    }

    mutating func release(_ axis: Axis) {
        if touches.remove(axis) != nil && source == .touch { stop() }
    }

    mutating func press(_ key: Key) {
        let starting = keys.isEmpty
        guard keys.insert(key).inserted else { return }
        if source == nil && starting { source = .keyboard }
        guard source == .keyboard else { return }
        forward = (keys.contains(.up) ? 1 : 0) - (keys.contains(.down) ? 1 : 0)
        turn = (keys.contains(.left) ? 1 : 0) - (keys.contains(.right) ? 1 : 0)
    }

    mutating func release(_ key: Key) {
        if keys.remove(key) != nil && source == .keyboard { stop() }
    }

    mutating func sampleController(forward y: Double, turn x: Double) {
        let y = Self.controllerRatio(y)
        let x = Self.controllerRatio(x)
        if x == 0 && y == 0 {
            if source == .controller { stop() }
            controllerArmed = true
        } else if source == .controller {
            if (forward != 0 && y == 0) || (turn != 0 && x == 0) {
                stop()
            } else {
                forward = y
                turn = x
            }
        } else if source == nil && controllerArmed {
            source = .controller
            forward = y
            turn = x
        } else {
            controllerArmed = false
        }
    }

    private static func controllerRatio(_ value: Double) -> Double {
        guard value.isFinite, abs(value) > 0.1 else { return 0 }
        return min(1, max(-1, value))
    }

    func velocity(linearLimit: Double, angularLimit: Double) -> RobotVelocity {
        guard linearLimit.isFinite, linearLimit > 0, angularLimit.isFinite, angularLimit > 0 else { return .zero }
        return RobotVelocity(linear: forward * linearLimit, angular: turn * angularLimit)
    }
}
