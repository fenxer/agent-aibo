import Foundation

/// CPU twin of the aibo-switch Metal shader (Shadertoy mask-warp).
///
/// The renderer lives in `App/Aibo/AiboSwitchTransition.metal`. Keep the two
/// in lockstep: cubic-in-out progress, GLSL-style `mod` mirror wrap, and a
/// threshold mix of the outgoing / incoming images.
public enum AiboSwitchTransition {
    /// Linear wall-clock length; easing happens inside the shader.
    public static let duration: TimeInterval = 0.8

    public static func cubicInOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        if x < 0.5 {
            return 4 * x * x * x
        }
        let u = 2 * x - 2
        return 0.5 * u * u * u + 1
    }

    /// GLSL `mod`: `x - y * floor(x / y)`. Swift `%` / `truncatingRemainder` differ for negatives.
    public static func glslMod(_ x: Double, _ y: Double) -> Double {
        guard y != 0 else { return 0 }
        return x - y * floor(x / y)
    }

    /// Ping-pong every unit interval so warped UVs stay inside the artwork.
    public static func mirror(_ v: Double) -> Double {
        let m = glslMod(v, 2)
        return m >= 1 ? 2 - m : m
    }

    /// Mix factor for the outgoing image (`1` = fully from, `0` = fully to).
    ///
    /// The original `S(mask - progress)` leaks the incoming image wherever the
    /// noise mask is below 1, even at progress 0. Anchor the ends so a switch
    /// starts as a still of `from` and finishes as a still of `to`.
    public static func stepMask(mask: Double, progress: Double) -> Double {
        let p = cubicInOut(progress)
        if p <= 0 { return 1 }
        if p >= 1 { return 0 }
        let v = mask - p
        if v <= 0 { return 0 }
        if v >= 1 { return 1 }
        return v
    }
}
