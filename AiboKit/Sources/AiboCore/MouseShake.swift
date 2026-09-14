import CoreGraphics
import Foundation

/// Tunables for the desktop “shake the pointer over Aibo” dodge.
///
/// Times are seconds. Distances are points unless noted. Release uses
/// `MouseShakeConfig()`. DEBUG settings may replace this live.
public struct MouseShakeConfig: Sendable, Equatable, Codable {
    public var strokeMinDistance: Double
    public var window: TimeInterval
    public var minReversals: Int
    public var minTravel: Double
    public var cooldown: TimeInterval
    public var proximityPadding: Double
    /// Dodge length as a multiple of the current aibo’s longer side.
    public var dodgeDistanceFactor: Double
    public var dodgeDuration: TimeInterval

    public init(
        strokeMinDistance: Double = 12,
        window: TimeInterval = 0.4,
        minReversals: Int = 3,
        minTravel: Double = 80,
        cooldown: TimeInterval = 0.7,
        proximityPadding: Double = 12,
        dodgeDistanceFactor: Double = 1.1,
        dodgeDuration: TimeInterval = 0.4
    ) {
        self.strokeMinDistance = strokeMinDistance
        self.window = window
        self.minReversals = minReversals
        self.minTravel = minTravel
        self.cooldown = cooldown
        self.proximityPadding = proximityPadding
        self.dodgeDistanceFactor = dodgeDistanceFactor
        self.dodgeDuration = dodgeDuration
    }
}

/// Counts rapid left/right reversals. Event-driven: the caller feeds mouse
/// samples; there is no timer.
public struct MouseShakeDetector: Sendable, Equatable {
    public var config: MouseShakeConfig
    private var samples: [Sample] = []
    private var lastTriggerTime: TimeInterval?

    public init(config: MouseShakeConfig = MouseShakeConfig()) {
        self.config = config
    }

    public mutating func reset() {
        samples.removeAll()
        lastTriggerTime = nil
    }

    /// Start cooldown and drop the buffer (used when a dodge begins from
    /// either a detected shake or a debug trigger).
    public mutating func markTriggered(at time: TimeInterval) {
        lastTriggerTime = time
        samples.removeAll()
    }

    /// Returns `true` when the recent samples count as a shake.
    public mutating func push(x: Double, time: TimeInterval, inProximity: Bool) -> Bool {
        if let lastTriggerTime, time - lastTriggerTime < config.cooldown {
            if !inProximity {
                samples.removeAll()
            }
            return false
        }
        if !inProximity {
            samples.removeAll()
            return false
        }

        samples.append(Sample(time: time, x: x))
        let window = max(config.window, 0)
        samples.removeAll { time - $0.time > window }

        guard evaluate() else { return false }
        markTriggered(at: time)
        return true
    }

    private func evaluate() -> Bool {
        guard samples.count >= 2 else { return false }
        let strokeMin = max(config.strokeMinDistance, 1)
        var travel = 0.0
        for index in 1..<samples.count {
            travel += abs(samples[index].x - samples[index - 1].x)
        }

        var lastSignificantX = samples[0].x
        var lastSign = 0
        var reversals = 0
        for sample in samples.dropFirst() {
            let dx = sample.x - lastSignificantX
            guard abs(dx) >= strokeMin else { continue }
            let sign = dx > 0 ? 1 : -1
            if lastSign != 0, sign != lastSign {
                reversals += 1
            }
            lastSign = sign
            lastSignificantX = sample.x
        }

        return reversals >= config.minReversals && travel >= config.minTravel
    }

    private struct Sample: Sendable, Equatable {
        var time: TimeInterval
        var x: Double
    }
}

/// Dodge toward the visible-frame center — away from the nearer screen edge.
///
/// The four 50%/50% quadrants are the same rule: top-left runs toward
/// bottom-right, and so on, along the line through the screen center.
public enum MouseShakeDodge: Sendable {
    /// Unit vector from `position` toward `visible`’s center.
    public static func direction(from position: CGPoint, in visible: CGRect) -> CGVector {
        let dx = visible.midX - position.x
        let dy = visible.midY - position.y
        let length = hypot(dx, dy)
        if length < 0.5 {
            let fallback = hypot(1.0, 1.0)
            return CGVector(dx: 1 / fallback, dy: 1 / fallback)
        }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    public static func target(
        from position: CGPoint,
        in visible: CGRect,
        distance: CGFloat,
        padding: CGFloat
    ) -> CGPoint {
        let vector = direction(from: position, in: visible)
        let unconstrained = CGPoint(
            x: position.x + vector.dx * distance,
            y: position.y + vector.dy * distance
        )
        return clamp(unconstrained, to: paddedBounds(visible, padding: padding))
    }

    public static func easedProgress(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max(elapsed / duration, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    public static func interpolate(from: CGPoint, to: CGPoint, progress: Double) -> CGPoint {
        let t = min(max(progress, 0), 1)
        return CGPoint(
            x: from.x + (to.x - from.x) * t,
            y: from.y + (to.y - from.y) * t
        )
    }

    public static func paddedBounds(_ visible: CGRect, padding: CGFloat) -> CGRect {
        let padX = min(padding, max(0, visible.width / 2 - 1))
        let padY = min(padding, max(0, visible.height / 2 - 1))
        return visible.insetBy(dx: padX, dy: padY)
    }

    public static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
