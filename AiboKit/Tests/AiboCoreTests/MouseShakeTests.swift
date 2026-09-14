import CoreGraphics
import Foundation
import Testing
@testable import AiboCore

private let config = MouseShakeConfig(
    strokeMinDistance: 12,
    window: 0.4,
    minReversals: 3,
    minTravel: 80,
    cooldown: 0.7
)

/// Left/right/left/right with 20pt strokes — three reversals.
private func shakeXs() -> [Double] {
    [0, 20, 0, 20, 0]
}

private func feed(
    _ detector: inout MouseShakeDetector,
    xs: [Double],
    start: TimeInterval,
    step: TimeInterval = 0.05,
    inProximity: Bool = true
) -> [Bool] {
    xs.enumerated().map { index, x in
        detector.push(x: x, time: start + TimeInterval(index) * step, inProximity: inProximity)
    }
}

@Test func mouseShakeNeedsThreeReversals() {
    var detector = MouseShakeDetector(config: config)

    // Two reversals: L → R → L (three points after origin = two turns).
    let twoTurns = feed(&detector, xs: [0, 20, 0, 20], start: 0)
    #expect(twoTurns.allSatisfy { !$0 })

    detector.reset()
    let triggered = feed(&detector, xs: shakeXs(), start: 0)
    #expect(triggered.last == true)
    #expect(triggered.dropLast().allSatisfy { !$0 })
}

@Test func mouseShakeIgnoresSlowOrOneWayMotion() {
    var detector = MouseShakeDetector(config: config)
    // Same path, but each sample is 0.2s apart → 0.8s span > 0.4s window.
    let slow = feed(&detector, xs: shakeXs(), start: 0, step: 0.2)
    #expect(slow.allSatisfy { !$0 })

    detector.reset()
    let sweep = feed(&detector, xs: [0, 30, 60, 90, 120], start: 10)
    #expect(sweep.allSatisfy { !$0 })
}

@Test func mouseShakeLeavingProximityClearsBuffer() {
    var detector = MouseShakeDetector(config: config)
    _ = feed(&detector, xs: [0, 20, 0, 20], start: 0)
    #expect(detector.push(x: 100, time: 0.3, inProximity: false) == false)

    // Need a full 3-reversal shake again.
    let after = feed(&detector, xs: shakeXs(), start: 1)
    #expect(after.last == true)
}

@Test func mouseShakeCooldownBlocksImmediateRetrigger() {
    var detector = MouseShakeDetector(config: config)
    #expect(feed(&detector, xs: shakeXs(), start: 0).last == true)

    let again = feed(&detector, xs: shakeXs(), start: 0.3)
    #expect(again.allSatisfy { !$0 })

    #expect(feed(&detector, xs: shakeXs(), start: 1.0).last == true)
}

@Test func mouseShakeTravelMustReachThreshold() {
    var tight = config
    tight.minTravel = 200
    var detector = MouseShakeDetector(config: tight)
    // 4 × 20pt = 80pt travel, below 200.
    #expect(feed(&detector, xs: shakeXs(), start: 0).allSatisfy { !$0 })
}

@Test func mouseShakeDodgeAimsAtOppositeQuadrant() {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let distance: CGFloat = 100
    let padding: CGFloat = 24

    // AppKit: y up. Top-left → toward bottom-right (screen center).
    let topLeft = CGPoint(x: 200, y: 800)
    let fromTopLeft = MouseShakeDodge.target(
        from: topLeft,
        in: visible,
        distance: distance,
        padding: padding
    )
    #expect(fromTopLeft.x > topLeft.x)
    #expect(fromTopLeft.y < topLeft.y)

    let bottomLeft = CGPoint(x: 200, y: 200)
    let fromBottomLeft = MouseShakeDodge.target(
        from: bottomLeft,
        in: visible,
        distance: distance,
        padding: padding
    )
    #expect(fromBottomLeft.x > bottomLeft.x)
    #expect(fromBottomLeft.y > bottomLeft.y)

    let topRight = CGPoint(x: 800, y: 800)
    let fromTopRight = MouseShakeDodge.target(
        from: topRight,
        in: visible,
        distance: distance,
        padding: padding
    )
    #expect(fromTopRight.x < topRight.x)
    #expect(fromTopRight.y < topRight.y)

    let bottomRight = CGPoint(x: 800, y: 200)
    let fromBottomRight = MouseShakeDodge.target(
        from: bottomRight,
        in: visible,
        distance: distance,
        padding: padding
    )
    #expect(fromBottomRight.x < bottomRight.x)
    #expect(fromBottomRight.y > bottomRight.y)
}

@Test func mouseShakeDodgeStaysInsidePaddedVisibleFrame() {
    let visible = CGRect(x: 0, y: 0, width: 400, height: 400)
    let padding: CGFloat = 24
    let bounds = MouseShakeDodge.paddedBounds(visible, padding: padding)
    let target = MouseShakeDodge.target(
        from: CGPoint(x: 40, y: 360),
        in: visible,
        distance: 2000,
        padding: padding
    )
    #expect(target.x >= bounds.minX && target.x <= bounds.maxX)
    #expect(target.y >= bounds.minY && target.y <= bounds.maxY)
}

@Test func mouseShakeDodgeEaseAndLerp() {
    #expect(MouseShakeDodge.easedProgress(elapsed: 0, duration: 0.4) == 0)
    #expect(MouseShakeDodge.easedProgress(elapsed: 0.4, duration: 0.4) == 1)
    #expect(MouseShakeDodge.easedProgress(elapsed: 1, duration: 0) == 1)
    let mid = MouseShakeDodge.easedProgress(elapsed: 0.2, duration: 0.4)
    #expect(mid > 0.5)
    #expect(mid < 1)

    let point = MouseShakeDodge.interpolate(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 10, y: 20),
        progress: 0.5
    )
    #expect(point.x == 5)
    #expect(point.y == 10)
}
