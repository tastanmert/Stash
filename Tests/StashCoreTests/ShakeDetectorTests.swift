import Foundation
import Testing
@testable import StashCore

/// Feeds a zigzag of `swings` half-strokes of `amplitude` points, 10 samples each, over `duration` seconds.
private func zigzag(_ detector: inout ShakeDetector, swings: Int, amplitude: Double, duration: TimeInterval, vertical: Bool = false) -> Bool {
    let steps = 10
    let total = swings * steps
    var position = 0.0
    var fired = false
    for i in 0...total {
        let swing = i / steps
        let direction = swing.isMultiple(of: 2) ? 1.0 : -1.0
        if i > 0 { position += direction * amplitude / Double(steps) }
        let t = duration * Double(i) / Double(total)
        let hit = vertical ? detector.add(x: 100, y: position, time: t) : detector.add(x: position, y: 100, time: t)
        fired = fired || hit
    }
    return fired
}

@Test(arguments: ShakeDetector.Sensitivity.allCases)
func `quick wide zigzag is a shake`(sensitivity: ShakeDetector.Sensitivity) {
    var d = ShakeDetector(sensitivity: sensitivity)
    #expect(zigzag(&d, swings: 6, amplitude: 60, duration: 0.45))
}

@Test func `vertical shaking counts too`() {
    var d = ShakeDetector()
    #expect(zigzag(&d, swings: 6, amplitude: 60, duration: 0.45, vertical: true))
}

@Test func `straight drag is not a shake`() {
    var d = ShakeDetector(sensitivity: .highest)
    var fired = false
    for i in 0...100 { fired = fired || d.add(x: Double(i) * 5, y: Double(i), time: Double(i) * 0.01) }
    #expect(!fired)
}

@Test func `slow wobble is not a shake`() {
    var d = ShakeDetector()
    #expect(!zigzag(&d, swings: 6, amplitude: 60, duration: 3))
}

@Test func `tiny jitter is not a shake`() {
    var d = ShakeDetector()
    #expect(!zigzag(&d, swings: 8, amplitude: 6, duration: 0.4))
}

@Test func `higher sensitivity needs fewer swings`() {
    var standard = ShakeDetector(sensitivity: .standard)
    var highest = ShakeDetector(sensitivity: .highest)
    #expect(!zigzag(&standard, swings: 3, amplitude: 40, duration: 0.3))
    #expect(zigzag(&highest, swings: 3, amplitude: 40, duration: 0.3))
}
