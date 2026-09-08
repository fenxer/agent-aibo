import CoreGraphics
import Foundation

/// Launch portal from the orange-ring playground, using the DialKit export in `tl3.md`
/// (not the source-file defaults in `App.tsx`). Character look is playground **v1**
/// (`PoliPop`: scale + CSS blur). The 64×64 particle assemble is a discarded sketch.
///
/// Web CSS sizes are about 2× the desktop aibo, so motion values are halved
/// into Swift points. Ring radius / thickness stay in shader world units.
public enum AiboLaunchPortalTimeline: Sendable {
    public static let webToAppScale: Double = 0.5

    /// Step 4 in the export is loop rest with the ring already gone.
    public static let duration: Double = 0.8 + 0.6 + 0.8

    public static let poliDelay: Double = 0.9
    /// Longest Poli track in the export (`scale.duration`).
    public static let poliClipDuration: Double = 0.6

    public static let xFrom: Double = 0
    public static let xTo: Double = 48 * webToAppScale
    public static let yFrom: Double = 0
    public static let yTo: Double = 24 * webToAppScale
    public static let arc: Double = 70 * webToAppScale
    /// Playground lands at 0.9 of the 400px img; desktop rest is 1.0 so divide by this.
    public static let webScaleTo: Double = 0.9
    public static let webScaleFrom: Double = 0.08

    public static let ringEase = CubicBezier(0.8, 0.0, 0.3, 1.0)
    public static let opacityEase = CubicBezier(0.8, 0.0, 0.3, 1.0)
    public static let blurEase = CubicBezier(0.16, 1.0, 0.3, 1.0)
    public static let scaleSpring = Spring(bounce: 0.5, visualDuration: 0.6)
    public static let opacityDuration: Double = 0.4
    public static let blurDuration: Double = 0.5
    public static let blurFrom: Double = 64 * webToAppScale
    public static let blurTo: Double = 0

    public enum Playback: Sendable {
        case forward
        case reverse
    }

    public static func frame(at time: Double, playback: Playback = .forward) -> Frame {
        let elapsed = max(0, time)
        let sampleTime: Double
        switch playback {
        case .forward:
            sampleTime = elapsed
        case .reverse:
            sampleTime = duration - elapsed
        }
        var frame = sample(at: sampleTime)
        frame.isFinished = elapsed >= duration
        return frame
    }

    private static func sample(at time: Double) -> Frame {
        let t = max(0, time)
        let ring = sampleRing(at: t)

        let poliElapsed = t - poliDelay
        let poliProgress: Double
        if poliElapsed <= 0 {
            poliProgress = 0
        } else {
            poliProgress = min(1, poliElapsed / poliClipDuration)
        }

        let scale: Double
        let opacity: Double
        let blur: Double
        let x: Double
        let y: Double
        if poliElapsed <= 0 {
            scale = webScaleFrom / webScaleTo
            opacity = 0
            blur = blurFrom
            x = xFrom
            y = yFrom
        } else {
            let webScale = lerp(webScaleFrom, webScaleTo, scaleSpring.progress(at: poliElapsed))
            scale = webScale / webScaleTo
            opacity = lerp(0, 1, opacityEase.value(at: min(1, poliElapsed / opacityDuration)))
            blur = lerp(blurFrom, blurTo, blurEase.value(at: min(1, poliElapsed / blurDuration)))
            x = lerp(xFrom, xTo, poliProgress)
            let chordY = lerp(yFrom, yTo, poliProgress)
            y = chordY - 4 * arc * poliProgress * (1 - poliProgress)
        }

        return Frame(
            ringRadius: ring.radius,
            ringOpacity: ring.opacity,
            ringThickness: ring.thickness,
            ringDepth: ring.depth,
            poliProgress: poliProgress,
            scale: scale,
            opacity: opacity,
            blur: blur,
            x: x,
            y: y,
            restRelativeX: x - xTo,
            restRelativeY: y - yTo,
            isFinished: false
        )
    }

    private struct RingKey: Equatable {
        var radius: Double
        var opacity: Double
        var thickness: Double
        var depth: Double
    }

    private struct RingStep {
        var duration: Double
        var ease: CubicBezier?
        var to: RingKey
    }

    /// `tl3.md` Ring.from + four steps. One-shot playback stops after step 3.
    private static let ringFrom = RingKey(radius: 0, opacity: 0, thickness: 0.34, depth: 0.35)
    private static let ringSteps: [RingStep] = [
        RingStep(
            duration: 0.8,
            ease: ringEase,
            to: RingKey(radius: 2, opacity: 1, thickness: 0.15, depth: 0.1)
        ),
        RingStep(
            duration: 0.6,
            ease: nil,
            to: RingKey(radius: 2, opacity: 1, thickness: 0.1, depth: 0.1)
        ),
        RingStep(
            duration: 0.8,
            ease: ringEase,
            to: RingKey(radius: 0, opacity: 0, thickness: 0.7, depth: 0.76)
        ),
        RingStep(
            duration: 0.7,
            ease: nil,
            to: RingKey(radius: 0, opacity: 0, thickness: 0.3, depth: 0.3)
        ),
    ]

    private static func sampleRing(at time: Double) -> RingKey {
        var start = ringFrom
        var remaining = time
        for step in ringSteps {
            if remaining <= step.duration {
                let linear = step.duration > 0 ? remaining / step.duration : 1
                let eased = step.ease?.value(at: linear) ?? min(max(linear, 0), 1)
                return RingKey(
                    radius: lerp(start.radius, step.to.radius, eased),
                    opacity: lerp(start.opacity, step.to.opacity, eased),
                    thickness: lerp(start.thickness, step.to.thickness, eased),
                    depth: lerp(start.depth, step.to.depth, eased)
                )
            }
            remaining -= step.duration
            start = step.to
        }
        return start
    }

    public static func layout(aiboSize: CGSize) -> Layout {
        Layout(aiboSize: aiboSize)
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

extension AiboLaunchPortalTimeline {
    public struct Frame: Equatable, Sendable {
        public var ringRadius: Double
        public var ringOpacity: Double
        public var ringThickness: Double
        public var ringDepth: Double
        public var poliProgress: Double
        public var scale: Double
        public var opacity: Double
        /// CSS `blur()` after the 2× downscale, in points.
        public var blur: Double
        /// Points, matching the playground `translate(x)` after the 2× downscale.
        public var x: Double
        /// Points, y-down, including the parabolic arc.
        public var y: Double
        /// `x` relative to the settled desktop slot (`xTo`). End of the jump is 0.
        public var restRelativeX: Double
        /// `y` relative to the settled desktop slot (`yTo`). End of the jump is 0.
        public var restRelativeY: Double
        public var isFinished: Bool
    }

    /// Extra panel chrome so the ring and jump path are not clipped.
    ///
    /// During playback the Metal view fills the panel. Rest is the real aibo
    /// slot (same math as the panel with no bubbles), not the view center.
    /// The ring is inferred at `(-xTo, -yTo)` from that rest pose.
    public struct Layout: Equatable, Sendable {
        public var canvas: CGSize
        public var aiboSize: CGSize
        public var extraLeading: CGFloat
        public var extraTrailing: CGFloat
        public var extraTop: CGFloat
        public var extraBottom: CGFloat

        /// Landing translation from the ring, in points. Ring center is the
        /// negation of this from the settled slot.
        public var xEnd: CGFloat { CGFloat(AiboLaunchPortalTimeline.xTo) }
        public var yEnd: CGFloat { CGFloat(AiboLaunchPortalTimeline.yTo) }

        public init(aiboSize: CGSize) {
            self.aiboSize = aiboSize
            let character = max(aiboSize.width, aiboSize.height)
            let ringRadius = character * 1.2
            let xLand = CGFloat(AiboLaunchPortalTimeline.xTo)
            let yLand = CGFloat(AiboLaunchPortalTimeline.yTo)
            let arc = CGFloat(AiboLaunchPortalTimeline.arc)
            let relYPeak = -(yLand / 2 + arc)
            let pad: CGFloat = 24
            let halfW = aiboSize.width / 2
            let halfH = aiboSize.height / 2

            let extentLeft = max(halfW, xLand + ringRadius, xLand + halfW)
            let extentRight = max(halfW, max(0, ringRadius - xLand))
            let extentTop = max(halfH, yLand + ringRadius, -relYPeak + halfH)
            let extentBottom = max(halfH, max(0, ringRadius - yLand))
            let canvas = CGSize(
                width: max((max(extentLeft, extentRight) + pad) * 2, 1),
                height: max((max(extentTop, extentBottom) + pad) * 2, 1)
            )
            self.canvas = canvas

            extraLeading = max(0, (canvas.width - aiboSize.width) / 2)
            extraTrailing = extraLeading
            extraTop = max(0, (canvas.height - aiboSize.height) / 2)
            extraBottom = extraTop
        }

        /// Flipped (y-down) center of the aibo slot in panel coordinates when
        /// no bubbles are shown. Matches `AiboPanelController.aiboOrigin` for
        /// `bubbleCount == 0`, converted from AppKit bottom-left.
        public func restCenterYDown(
            panelSize: CGSize,
            leading: CGFloat,
            trailing: CGFloat,
            top: CGFloat,
            bottom: CGFloat,
            placement: BubblePlacement
        ) -> CGPoint {
            let contentWidth = panelSize.width - leading - trailing
            let originX: CGFloat
            let originYAppKit: CGFloat
            switch placement {
            case .top:
                originX = leading + (contentWidth - aiboSize.width) / 2
                originYAppKit = bottom
            case .bottom:
                originX = leading + (contentWidth - aiboSize.width) / 2
                originYAppKit = panelSize.height - top - aiboSize.height
            case .left:
                originX = panelSize.width - trailing - aiboSize.width
                originYAppKit = bottom
            case .right:
                originX = leading
                originYAppKit = bottom
            }
            let centerAppKit = CGPoint(
                x: originX + aiboSize.width / 2,
                y: originYAppKit + aiboSize.height / 2
            )
            return CGPoint(x: centerAppKit.x, y: panelSize.height - centerAppKit.y)
        }
    }

    public struct CubicBezier: Equatable, Sendable {
        public var x1: Double
        public var y1: Double
        public var x2: Double
        public var y2: Double

        public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            self.x1 = x1
            self.y1 = y1
            self.x2 = x2
            self.y2 = y2
        }

        public func value(at p: Double) -> Double {
            let p = min(max(p, 0), 1)
            if p == 0 { return 0 }
            if p == 1 { return 1 }
            var t = p
            for _ in 0..<8 {
                let x = axis(t, x1, x2) - p
                if abs(x) < 1e-5 { return axis(t, y1, y2) }
                let dx = axisDerivative(t, x1, x2)
                if abs(dx) < 1e-6 { break }
                t -= x / dx
            }
            var lo = 0.0
            var hi = 1.0
            t = p
            while hi - lo > 1e-5 {
                if axis(t, x1, x2) < p {
                    lo = t
                } else {
                    hi = t
                }
                t = (lo + hi) / 2
            }
            return axis(t, y1, y2)
        }

        private func axis(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
            (1 - 3 * a2 + 3 * a1) * t * t * t
                + (3 * a2 - 6 * a1) * t * t
                + 3 * a1 * t
        }

        private func axisDerivative(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
            3 * (1 - 3 * a2 + 3 * a1) * t * t
                + 2 * (3 * a2 - 6 * a1) * t
                + 3 * a1
        }
    }

    /// DialKit `bounce` + `visualDuration` spring (same formulas as the playground).
    public struct Spring: Equatable, Sendable {
        public var bounce: Double
        public var visualDuration: Double

        public init(bounce: Double, visualDuration: Double) {
            self.bounce = bounce
            self.visualDuration = visualDuration
        }

        public var settleDuration: Double {
            let params = physics
            let w0 = sqrt(params.stiffness / params.mass)
            let zeta = params.damping / (2 * sqrt(params.stiffness * params.mass))
            let decay: Double
            if zeta >= 1 {
                decay = zeta * w0 - w0 * sqrt(max(0, zeta * zeta - 1))
            } else {
                decay = zeta * w0
            }
            let duration = log(200) / max(decay, 1e-6)
            return min(max(duration, 0.05), 10)
        }

        public func progress(at time: Double) -> Double {
            if time <= 0 { return 0 }
            let params = physics
            if time >= settleDuration { return 1 }
            let w0 = sqrt(params.stiffness / params.mass)
            let zeta = params.damping / (2 * sqrt(params.stiffness * params.mass))
            if zeta < 0.9999 {
                let wd = w0 * sqrt(1 - zeta * zeta)
                return 1 - exp(-zeta * w0 * time)
                    * (cos(wd * time) + zeta * w0 / wd * sin(wd * time))
            }
            if zeta < 1.0001 {
                return 1 - exp(-w0 * time) * (1 + w0 * time)
            }
            let wd = w0 * sqrt(zeta * zeta - 1)
            let r1 = -zeta * w0 + wd
            let r2 = -zeta * w0 - wd
            return 1 + (r2 * exp(r1 * time) - r1 * exp(r2 * time)) / (r1 - r2)
        }

        private var physics: (stiffness: Double, damping: Double, mass: Double) {
            let visualDuration = max(0.05, visualDuration)
            let root = 2 * Double.pi / (visualDuration * 1.2)
            let stiffness = root * root
            let damping = 2 * min(1, max(0.05, 1 - bounce)) * sqrt(stiffness)
            return (stiffness, damping, 1)
        }
    }
}
