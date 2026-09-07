import AppKit
import Metal
import QuartzCore
import simd

/// Demo-derived plasma fill for the Codex TODO capsule background.
///
/// Size / radius / track color come from the live capsule. Wave and color
/// knobs (other than track) match the shader-progress playground snapshot.
@MainActor
final class CapsulePlanShaderRenderer {
    static let shared: CapsulePlanShaderRenderer? = CapsulePlanShaderRenderer()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: MTLCompileOptions())
        } catch {
            #if DEBUG
            print("CapsulePlanShaderRenderer: shader compile failed: \(error)")
            #endif
            return nil
        }
        guard let vertex = library.makeFunction(name: "capsule_plan_vertex"),
              let fragment = library.makeFunction(name: "capsule_plan_fragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func configure(_ layer: CAMetalLayer) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = true
        layer.framebufferOnly = true
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
    }

    func draw(layer: CAMetalLayer, uniforms: CapsulePlanUniforms) {
        guard layer.drawableSize.width >= 1, layer.drawableSize.height >= 1,
              let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer()
        else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(
            Double(uniforms.trackColor.x),
            Double(uniforms.trackColor.y),
            Double(uniforms.trackColor.z),
            1
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        var uniforms = uniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CapsulePlanUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// Matches the Metal `CapsulePlanUniforms` layout (21 scalars, 16-byte pad, then 9 float4s).
struct CapsulePlanUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var progress: Float
    var speed: Float
    var churn: Float
    var lag: Float
    var echo: Float
    var fillStart: Float
    var fillEnd: Float
    var edge: Float
    var falloff: Float
    var bloom: Float
    var ripple: Float
    var trails: Float
    var trailGlow: Float
    var haze: Float
    var dither: Float
    var tailOpacity: Float
    var tailLength: Float
    /// Playground `Size.width` in device pixels (`200 * min(dpr, 2)`).
    var refBarWidth: Float
    var trackColor: SIMD4<Float>
    var deepColor: SIMD4<Float>
    var midColor: SIMD4<Float>
    var glowColor: SIMD4<Float>
    var brightColor: SIMD4<Float>
    var coreColor: SIMD4<Float>
    var trailColor: SIMD4<Float>
    var trailHotColor: SIMD4<Float>
    var tailColor: SIMD4<Float>
}

enum CapsulePlanShaderStyle {
    /// Playground `Color.primary`.
    static let primary = simdColor(hex: 0x0935E5)
    /// Playground `Tail.color`.
    static let tail = simdColor(hex: 0x2222E7)

    static let speed: Float = 1
    static let churn: Float = 1
    static let lag: Float = 0.7
    static let echo: Float = 1
    static let fillStart: Float = 0
    static let fillEnd: Float = 1
    static let edge: Float = 0.75
    static let falloff: Float = 0.45
    static let bloom: Float = 1.05
    static let ripple: Float = 1.6
    static let trails: Float = 0.1
    static let trailGlow: Float = 1.55
    static let haze: Float = 1
    static let dither: Float = 0.85
    static let tailOpacity: Float = 0.7
    static let tailLength: Float = 2
    /// Playground `Size.width` in CSS pixels; demo draws at `width * min(dpr, 2)`.
    static let playgroundBarWidth: CGFloat = 200

    private static let derived = derivedPalette(from: primary)

    static func uniforms(
        resolution: SIMD2<Float>,
        time: Float,
        progress: Float,
        track: SIMD3<Float>,
        backingScale: CGFloat
    ) -> CapsulePlanUniforms {
        let colors = derived
        let track4 = SIMD4<Float>(track.x, track.y, track.z, 1)
        let scale = min(max(backingScale, 1), 2)
        return CapsulePlanUniforms(
            resolution: resolution,
            time: time,
            progress: max(0, min(1, progress)),
            speed: speed,
            churn: churn,
            lag: lag,
            echo: echo,
            fillStart: fillStart,
            fillEnd: fillEnd,
            edge: edge,
            falloff: falloff,
            bloom: bloom,
            ripple: ripple,
            trails: trails,
            trailGlow: trailGlow,
            haze: haze,
            dither: dither,
            tailOpacity: tailOpacity,
            tailLength: tailLength,
            refBarWidth: Float(playgroundBarWidth * scale),
            trackColor: track4,
            deepColor: SIMD4<Float>(tail.x, tail.y, tail.z, 1),
            midColor: colors.mid,
            glowColor: colors.glow,
            brightColor: colors.bright,
            coreColor: colors.core,
            trailColor: colors.trail,
            trailHotColor: colors.trailHot,
            tailColor: SIMD4<Float>(tail.x, tail.y, tail.z, 1)
        )
    }

    static func simdColor(from color: NSColor) -> SIMD3<Float> {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return SIMD3<Float>(0, 0, 0)
        }
        return SIMD3<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent)
        )
    }

    private static func simdColor(hex: UInt32) -> SIMD3<Float> {
        SIMD3<Float>(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255
        )
    }

    private struct DerivedPalette {
        var mid: SIMD4<Float>
        var glow: SIMD4<Float>
        var bright: SIMD4<Float>
        var core: SIMD4<Float>
        var trail: SIMD4<Float>
        var trailHot: SIMD4<Float>
    }

    private static func derivedPalette(from primary: SIMD3<Float>) -> DerivedPalette {
        let hsl = rgbToHsl(primary)
        let mid = hslToRgb(h: hsl.h + 8, s: max(hsl.s * 0.95, 0.7), l: 0.16)
        let glow = hslToRgb(h: hsl.h + 4, s: max(hsl.s, 0.85), l: 0.38)
        let core = hslToRgb(h: hsl.h - 6, s: min(hsl.s * 0.6, 0.45), l: 0.88)
        return DerivedPalette(
            mid: SIMD4<Float>(mid.x, mid.y, mid.z, 1),
            glow: SIMD4<Float>(glow.x, glow.y, glow.z, 1),
            bright: SIMD4<Float>(primary.x, primary.y, primary.z, 1),
            core: SIMD4<Float>(core.x, core.y, core.z, 1),
            trail: SIMD4<Float>(glow.x, glow.y, glow.z, 1),
            trailHot: SIMD4<Float>(primary.x, primary.y, primary.z, 1)
        )
    }

    private static func rgbToHsl(_ rgb: SIMD3<Float>) -> (h: Float, s: Float, l: Float) {
        let maxC = max(rgb.x, max(rgb.y, rgb.z))
        let minC = min(rgb.x, min(rgb.y, rgb.z))
        let l = (maxC + minC) * 0.5
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Float
        if maxC == rgb.x {
            h = (rgb.y - rgb.z) / d + (rgb.y < rgb.z ? 6 : 0)
        } else if maxC == rgb.y {
            h = (rgb.z - rgb.x) / d + 2
        } else {
            h = (rgb.x - rgb.y) / d + 4
        }
        return (h * 60, s, l)
    }

    private static func hslToRgb(h: Float, s: Float, l: Float) -> SIMD3<Float> {
        var hue = h.truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        let hn = hue / 360
        let sn = max(0, min(1, s))
        let ln = max(0, min(1, l))
        if sn == 0 { return SIMD3<Float>(repeating: ln) }
        let q = ln < 0.5 ? ln * (1 + sn) : ln + sn - ln * sn
        let p = 2 * ln - q
        return SIMD3<Float>(
            hue2rgb(p: p, q: q, t: hn + 1 / 3),
            hue2rgb(p: p, q: q, t: hn),
            hue2rgb(p: p, q: q, t: hn - 1 / 3)
        )
    }

    private static func hue2rgb(p: Float, q: Float, t: Float) -> Float {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1 / 6 { return p + (q - p) * 6 * t }
        if t < 1 / 2 { return q }
        if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
        return p
    }
}

extension CapsulePlanShaderRenderer {
    /// Plasma fill from shader-progress. The drawable *is* the bar (capsule
    /// clip lives in SwiftUI); page dots / outer bloom are omitted.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float2 resolution;
        float time;
        float progress;
        float speed;
        float churn;
        float lag;
        float echo;
        float fillStart;
        float fillEnd;
        float edge;
        float falloff;
        float bloom;
        float ripple;
        float trails;
        float trailGlow;
        float haze;
        float dither;
        float tailOpacity;
        float tailLength;
        float refBarWidth;
        float4 trackColor;
        float4 deepColor;
        float4 midColor;
        float4 glowColor;
        float4 brightColor;
        float4 coreColor;
        float4 trailColor;
        float4 trailHotColor;
        float4 tailColor;
    };

    vertex VertexOut capsule_plan_vertex(uint vid [[vertex_id]]) {
        float2 pos = float2((vid << 1) & 2, vid & 2);
        VertexOut out;
        out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(pos.x, 1.0 - pos.y);
        return out;
    }

    float hash21(float2 p) {
        p = fract(p * float2(234.34, 435.345));
        p += dot(p, p + 34.23);
        return fract(p.x * p.y);
    }

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    float interleavedGradientNoise(float2 screenPos) {
        float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
        return fract(magic.z * fract(dot(screenPos, magic.xy)));
    }

    fragment float4 capsule_plan_fragment(
        VertexOut in [[stage_in]],
        constant Uniforms &u [[buffer(0)]]
    ) {
        float2 barUv = saturate(in.uv);
        float2 pixelCoord = barUv * u.resolution;

        // Playground distances are bar-UV tuned for Size.width CSS pixels.
        // Map this capsule into that space so haze / falloff / ribbons keep
        // the same pixel length instead of shrinking with the bubble.
        float ourOverRef = u.resolution.x / max(u.refBarWidth, 1.0);
        float refOverOur = 1.0 / max(ourOverRef, 0.0001);

        float effProgress = mix(u.fillStart, u.fillEnd, saturate(u.progress));
        float arcFactor = 4.0 * barUv.y * (1.0 - barUv.y);
        float bow = (arcFactor - 0.25) * (u.edge * 0.018) * refOverOur;

        float tSpeed = u.time * u.speed;
        float tChurn = u.time * u.churn;

        float frontMicroWave = sin(barUv.y * 10.0 - tSpeed * 2.5) * (u.ripple * 0.0035) * refOverOur;
        float frontX = effProgress + bow + frontMicroWave;
        float distToFront = barUv.x - frontX;
        float distRef = distToFront * ourOverRef;

        float wave2Offset = (sin(barUv.y * 15.0 - tSpeed * 3.2 + 2.1) * (u.ripple * 0.013)
            + cos(barUv.y * 22.0 + tChurn * 1.4) * (u.churn * 0.006)) * refOverOur;
        float x2 = effProgress + bow * 0.55 - 0.038 * max(u.echo, 0.15) * refOverOur + wave2Offset;

        float wave3Offset = (cos(barUv.y * 9.0 + tSpeed * 1.8 - 1.2) * (u.ripple * 0.017)
            + sin(barUv.y * 28.0 - tChurn * 1.9) * (u.churn * 0.008)) * refOverOur;
        float x3 = effProgress + bow * 0.25 - 0.082 * max(u.echo, 0.15) * refOverOur + wave3Offset;

        float3 barColor = u.trackColor.rgb;

        if (distRef < 0.25) {
            float innerDist = max(0.0, -distToFront);
            float innerRef = innerDist * ourOverRef;
            float lagPhase = innerRef * (u.lag * 16.0);
            float churnNoise = noise(float2(barUv.x * 5.0 * ourOverRef - tSpeed * 0.8, barUv.y * 7.0 + tChurn * 0.8))
                * u.churn * 0.5;

            float distW2 = (barUv.x - x2) * ourOverRef;
            float w1 = sin(distW2 * 110.0 + sin(barUv.y * 14.0 - tSpeed * 2.2 + lagPhase)
                * (2.0 + u.ripple * 2.5) + churnNoise);
            float trail1 = pow(saturate(1.0 - abs(w1)), 14.0 / max(u.trails, 0.08));

            float distW3 = (barUv.x - x3) * ourOverRef;
            float w2 = sin(distW3 * 85.0 + cos(barUv.y * 18.0 + tSpeed * 1.6 - lagPhase * 0.6)
                * (2.4 + u.ripple * 3.0) - churnNoise);
            float trail2 = pow(saturate(1.0 - abs(w2)), 16.0 / max(u.trails, 0.08));

            float midX = (x2 + x3) * 0.5;
            float distMid = (barUv.x - midX) * ourOverRef;
            float w3 = sin(distMid * 130.0 + sin(barUv.y * 24.0 + tSpeed * 2.8)
                * (1.8 + u.ripple * 2.0));
            float trail3 = pow(saturate(1.0 - abs(w3)), 12.0 / max(u.trails, 0.08));

            float allTrails = (trail1 * 0.85 + trail2 * 0.75 + trail3 * 0.5) * u.trailGlow;
            allTrails *= exp(-innerRef * 4.5);

            float coreLine = exp(-innerRef * 160.0) * 2.2;
            float edgeAura = exp(-innerRef * (14.0 / max(u.falloff, 0.02)));

            float d2 = abs(barUv.x - x2) * ourOverRef;
            float echo1 = exp(-d2 * 68.0) * (0.80 * u.echo);
            echo1 *= smoothstep(0.015, -0.005, distRef);

            float d3 = abs(barUv.x - x3) * ourOverRef;
            float echo2 = exp(-d3 * 48.0) * (0.60 * u.echo);
            echo2 *= smoothstep(0.015, -0.005, distRef);

            float intersection = (echo1 * echo2) * 2.4;
            float hazePerturb = sin(barUv.x * 12.0 * ourOverRef - tSpeed + sin(barUv.y * 6.0) * 2.0) * 0.25 * u.haze;

            float3 baseTail = mix(u.trackColor.rgb, u.tailColor.rgb, saturate(u.tailOpacity));
            float bodyDecayRate = 3.2 / max(u.tailLength, 0.1);
            float fillProgressDepth = smoothstep(0.0, 0.85, 1.0 - innerRef * bodyDecayRate);
            float3 solidFluid = mix(baseTail, u.midColor.rgb, fillProgressDepth)
                * (1.0 + hazePerturb * fillProgressDepth);
            float3 fluidBody = mix(u.trackColor.rgb, solidFluid, saturate(u.tailOpacity));

            allTrails *= fillProgressDepth;
            echo1 *= fillProgressDepth;
            echo2 *= fillProgressDepth;
            fluidBody += u.glowColor.rgb * (0.35 * u.haze * exp(-innerRef * 6.0) * fillProgressDepth);

            float3 activeColor = fluidBody;
            activeColor += u.glowColor.rgb * (edgeAura * 0.85);
            activeColor += u.glowColor.rgb * (echo2 * 0.75);
            activeColor += u.brightColor.rgb * (echo1 * 0.85);
            float3 trailTint = mix(u.trailColor.rgb, u.trailHotColor.rgb, saturate(allTrails * 0.8));
            activeColor += trailTint * allTrails;
            activeColor += u.coreColor.rgb * intersection;
            activeColor += u.brightColor.rgb * (coreLine * 0.95 + edgeAura * 0.45);
            float centerHotspot = 1.0 - abs(barUv.y - 0.5) * 1.2;
            activeColor += u.coreColor.rgb
                * (pow(clamp(coreLine * 0.8, 0.0, 2.0), 1.5) * clamp(centerHotspot, 0.4, 1.2));

            float frontTransition = smoothstep(0.003, -0.002, distRef);
            barColor = mix(barColor, activeColor, frontTransition);
        }

        if (distRef >= -0.01) {
            float outerDist = distRef;
            float forwardBloom = exp(-outerDist * (32.0 / max(u.falloff, 0.02))) * (u.bloom * 1.3);
            float forwardSoft = exp(-outerDist * (10.0 / max(u.falloff, 0.02))) * (u.bloom * 0.4);
            barColor += mix(u.glowColor.rgb, u.brightColor.rgb, 0.5) * forwardBloom
                + u.glowColor.rgb * (forwardSoft * 0.25);
        }

        float ign = interleavedGradientNoise(pixelCoord);
        barColor += float3((ign - 0.5) * (u.dither * 0.05));
        barColor = saturate(barColor);
        return float4(barColor, 1.0);
    }
    """
}
