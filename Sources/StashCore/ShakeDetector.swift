import Foundation

/// Recognizes a "shake" in a stream of cursor positions: several quick direction
/// reversals along either axis within a short time window.
public struct ShakeDetector: Sendable {
    public enum Sensitivity: String, CaseIterable, Codable, Sendable {
        case standard, high, highest

        /// Reversals needed, the minimum travel (points) before a turn counts, and the time window.
        var reversals: Int { switch self { case .standard: 4; case .high: 3; case .highest: 2 } }
        var minTravel: Double { switch self { case .standard: 24; case .high: 16; case .highest: 10 } }
        var window: TimeInterval { switch self { case .standard: 0.55; case .high: 0.65; case .highest: 0.8 } }
    }

    private struct Axis {
        var direction = 0          // -1, 0, +1
        var travel = 0.0           // distance moved in `direction` since the last turn
        var pending = 0.0          // distance moved against `direction`
    }

    public var sensitivity: Sensitivity
    private var x = Axis(), y = Axis()
    private var last: (x: Double, y: Double)?
    private var turns: [TimeInterval] = []

    public init(sensitivity: Sensitivity = .standard) {
        self.sensitivity = sensitivity
    }

    public mutating func reset() {
        x = Axis(); y = Axis(); last = nil; turns.removeAll()
    }

    /// Feeds one cursor sample. Returns true once when a shake is recognized, then starts over.
    public mutating func add(x px: Double, y py: Double, time: TimeInterval) -> Bool {
        defer { last = (px, py) }
        guard let last else { return false }
        let turnedX = Self.track(&x, delta: px - last.x, minTravel: sensitivity.minTravel)
        let turnedY = Self.track(&y, delta: py - last.y, minTravel: sensitivity.minTravel)
        if turnedX || turnedY { turns.append(time) }
        turns.removeAll { time - $0 > sensitivity.window }
        guard turns.count >= sensitivity.reversals else { return false }
        reset()
        return true
    }

    /// Returns true when the axis reverses after enough travel each way.
    private static func track(_ axis: inout Axis, delta: Double, minTravel: Double) -> Bool {
        guard delta != 0 else { return false }
        let sign = delta > 0 ? 1 : -1
        if axis.direction == 0 {
            axis.direction = sign
            axis.travel = abs(delta)
            return false
        }
        if sign == axis.direction {
            axis.travel += abs(delta)
            axis.pending = 0
            return false
        }
        axis.pending += abs(delta)
        guard axis.pending >= minTravel else { return false }
        let counts = axis.travel >= minTravel
        axis.direction = sign
        axis.travel = axis.pending
        axis.pending = 0
        return counts
    }
}
