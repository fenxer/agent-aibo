import AiboCore
import AppKit
import Metal
import QuartzCore
import simd

/// Runtime-compiled Metal port of the orange-ring playground portal + v1 scale/blur pop.
@MainActor
final class AiboLaunchPortalRenderer {
    static let shared: AiboLaunchPortalRenderer? = AiboLaunchPortalRenderer()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let ringPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    private let linearSampler: MTLSamplerState
    private let nearestSampler: MTLSamplerState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: MTLCompileOptions())
        } catch {
            #if DEBUG
            print("AiboLaunchPortalRenderer: shader compile failed: \(error)")
            #endif
            return nil
        }

        guard let ringVertex = library.makeFunction(name: "aibo_portal_fs_vertex"),
              let ringFragment = library.makeFunction(name: "aibo_portal_ring_fragment"),
              let spriteVertex = library.makeFunction(name: "aibo_portal_sprite_vertex"),
              let spriteFragment = library.makeFunction(name: "aibo_portal_sprite_fragment")
        else { return nil }

        func pipeline(
            vertex: MTLFunction,
            fragment: MTLFunction
        ) -> MTLRenderPipelineState? {
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
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        let linearDescriptor = MTLSamplerDescriptor()
        linearDescriptor.minFilter = .linear
        linearDescriptor.magFilter = .linear
        linearDescriptor.mipFilter = .linear
        linearDescriptor.sAddressMode = .clampToEdge
        linearDescriptor.tAddressMode = .clampToEdge

        let nearestDescriptor = MTLSamplerDescriptor()
        nearestDescriptor.minFilter = .nearest
        nearestDescriptor.magFilter = .nearest
        nearestDescriptor.sAddressMode = .clampToEdge
        nearestDescriptor.tAddressMode = .clampToEdge

        guard let ringPipeline = pipeline(vertex: ringVertex, fragment: ringFragment),
              let spritePipeline = pipeline(vertex: spriteVertex, fragment: spriteFragment),
              let linearSampler = device.makeSamplerState(descriptor: linearDescriptor),
              let nearestSampler = device.makeSamplerState(descriptor: nearestDescriptor)
        else { return nil }

        self.device = device
        self.queue = queue
        self.ringPipeline = ringPipeline
        self.spritePipeline = spritePipeline
        self.linearSampler = linearSampler
        self.nearestSampler = nearestSampler
    }

    func makeTexture(from image: NSImage) -> MTLTexture? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: pointer.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                          | CGBitmapInfo.byteOrder32Little.rawValue
                  )
            else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        descriptor.mipmapLevelCount = max(1, Int(floor(log2(Double(max(width, height))))) + 1)
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
        if let blit = queue.makeCommandBuffer(),
           let encoder = blit.makeBlitCommandEncoder()
        {
            encoder.generateMipmaps(for: texture)
            encoder.endEncoding()
            blit.commit()
            blit.waitUntilCompleted()
        }
        return texture
    }

    func configure(_ layer: CAMetalLayer) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.backgroundColor = CGColor.clear
    }

    func draw(
        layer: CAMetalLayer,
        texture: MTLTexture,
        frame: AiboLaunchPortalTimeline.Frame,
        aiboSize: CGSize,
        nearestSprite: Bool,
        elapsed: Float
    ) {
        guard layer.drawableSize.width >= 1, layer.drawableSize.height >= 1,
              let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer()
        else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let resolution = SIMD2<Float>(
            Float(layer.drawableSize.width),
            Float(layer.drawableSize.height)
        )
        let scale = Float(layer.contentsScale)
        let slotSize = SIMD2<Float>(
            Float(aiboSize.width) * scale,
            Float(aiboSize.height) * scale
        )
        // The live sprite uses resizeAspect / scaledToFit inside this slot.
        // A non-square texture must not stretch to the square non-pixel layout.
        let sourceSize = SIMD2<Float>(Float(texture.width), Float(texture.height))
        let fit = min(slotSize.x / sourceSize.x, slotSize.y / sourceSize.y)
        let charSize = sourceSize * fit
        // This view is AppKit-centered on the aibo slot; landing is drawable center.
        let offset = SIMD2<Float>(
            Float(frame.restRelativeX) * scale,
            Float(frame.restRelativeY) * scale
        )
        let land = SIMD2<Float>(
            Float(AiboLaunchPortalTimeline.xTo) * scale,
            Float(AiboLaunchPortalTimeline.yTo) * scale
        )

        if frame.ringOpacity > 0.002 {
            var ring = AiboLaunchPortalRingUniforms(
                resolution: resolution,
                time: elapsed,
                radius: Float(frame.ringRadius),
                thickness: Float(frame.ringThickness),
                depth: Float(frame.ringDepth),
                speed: AiboLaunchPortalStyle.speed,
                rotSpeed: AiboLaunchPortalStyle.rotSpeed,
                twist: AiboLaunchPortalStyle.twist,
                warp: AiboLaunchPortalStyle.warp,
                warpTime: AiboLaunchPortalStyle.warpTime,
                glow: AiboLaunchPortalStyle.glow,
                pulse: AiboLaunchPortalStyle.pulse,
                hue: AiboLaunchPortalStyle.hue,
                camDist: AiboLaunchPortalStyle.camDist,
                focal: AiboLaunchPortalStyle.focal,
                exposure: AiboLaunchPortalStyle.exposure,
                vignette: AiboLaunchPortalStyle.vignette,
                opacity: Float(frame.ringOpacity),
                land: land
            )
            encoder.setRenderPipelineState(ringPipeline)
            encoder.setFragmentBytes(&ring, length: MemoryLayout<AiboLaunchPortalRingUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        if frame.opacity > 0.01 {
            var sprite = AiboLaunchPortalSpriteUniforms(
                resolution: resolution,
                charSize: charSize,
                offset: offset,
                scale: Float(frame.scale),
                opacity: Float(frame.opacity),
                blur: Float(frame.blur) * scale
            )
            encoder.setRenderPipelineState(spritePipeline)
            encoder.setVertexBytes(
                &sprite,
                length: MemoryLayout<AiboLaunchPortalSpriteUniforms>.stride,
                index: 0
            )
            encoder.setFragmentBytes(
                &sprite,
                length: MemoryLayout<AiboLaunchPortalSpriteUniforms>.stride,
                index: 0
            )
            encoder.setFragmentTexture(texture, index: 0)
            let blurred = frame.blur > 0.5
            encoder.setFragmentSamplerState(
                (nearestSprite && !blurred) ? nearestSampler : linearSampler,
                index: 0
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

enum AiboLaunchPortalStyle {
    static let speed: Float = 1
    static let rotSpeed: Float = 2.5
    static let twist: Float = 14
    static let warp: Float = 1
    static let warpTime: Float = 2
    static let glow: Float = 2
    static let pulse: Float = 4.5
    static let hue: Float = 0
    static let camDist: Float = 8
    static let focal: Float = 1.4
    static let exposure: Float = 1
    static let vignette: Float = 0.2
}

struct AiboLaunchPortalRingUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var radius: Float
    var thickness: Float
    var depth: Float
    var speed: Float
    var rotSpeed: Float
    var twist: Float
    var warp: Float
    var warpTime: Float
    var glow: Float
    var pulse: Float
    var hue: Float
    var camDist: Float
    var focal: Float
    var exposure: Float
    var vignette: Float
    var opacity: Float
    var landPad: Float = 0
    var land: SIMD2<Float>
}

struct AiboLaunchPortalSpriteUniforms {
    var resolution: SIMD2<Float>
    var charSize: SIMD2<Float>
    var offset: SIMD2<Float>
    var scale: Float
    var opacity: Float
    var blur: Float
    var pad: Float = 0
}

extension AiboLaunchPortalRenderer {
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct RingUniforms {
        float2 resolution;
        float time;
        float radius;
        float thickness;
        float depth;
        float speed;
        float rotSpeed;
        float twist;
        float warp;
        float warpTime;
        float glow;
        float pulse;
        float hue;
        float camDist;
        float focal;
        float exposure;
        float vignette;
        float opacity;
        float landPad;
        float2 land;
    };

    struct SpriteUniforms {
        float2 resolution;
        float2 charSize;
        float2 offset;
        float scale;
        float opacity;
        float blur;
        float pad;
    };

    struct VertexOut {
        float4 position [[position]];
    };

    struct SpriteOut {
        float4 position [[position]];
        float2 uv;
        float opacity;
    };

    constant float PI = 3.14159265;

    vertex VertexOut aibo_portal_fs_vertex(uint vid [[vertex_id]]) {
        float2 pos = float2((vid << 1) & 2, vid & 2);
        VertexOut out;
        out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    float3 triwave(float3 x) {
        return abs(fract(0.5 * x / PI - 0.25) - 0.5) * 4.0 - 1.0;
    }

    fragment half4 aibo_portal_ring_fragment(
        VertexOut in [[stage_in]],
        constant RingUniforms &u [[buffer(0)]]
    ) {
        float2 r = u.resolution;
        // View is centered on the aibo slot. `land` is y-down from ring to rest.
        float2 ringCenter = float2(r.x * 0.5 - u.land.x, r.y * 0.5 + u.land.y);
        // Volumetric glow has a nonzero tail. Fade it radially to transparent
        // before the nearest drawable edge, otherwise the canvas shows as a rectangle.
        float2 edgeDistance = min(ringCenter, r - ringCenter);
        float fadeRadius = max(min(edgeDistance.x, edgeDistance.y) - 1.0, 1.0);
        float distanceFromRing = length(in.position.xy - ringCenter) / fadeRadius;
        float edgeFade = 1.0 - smoothstep(0.6, 1.0, distanceFromRing);
        if (edgeFade <= 0.0) return half4(0.0);

        float2 uv = (in.position.xy - ringCenter) * 2.0 / r.y;
        float t = u.time * u.speed;

        float3 cam_pos = float3(0.0, 0.0, u.camDist);
        float3 P = float3(0.0);
        float3 rd = normalize(float3(uv, -u.focal));

        float d = 0.0;
        float z = 0.0;
        float4 o = float4(0.0, 0.0, 0.0, 1.0);

        for (int i = 0; i < 65; i++) {
            if (z >= 1e3) break;

            float3 p = z * rd + cam_pos;
            float D = length(float2(length(p.xy - P.xy) - u.radius, p.z - P.z));

            float T = u.rotSpeed * t - d * u.twist;
            float c = cos(T);
            float s = sin(T);
            float3 q = p - P;
            q.xy = float2x2(float2(c, s), float2(-s, c)) * q.xy;

            float w = 1.0;
            for (int k = 0; k < 8; k++) {
                w += 1.0;
                q += triwave((q * w + t * u.warpTime) * u.warp).yzx / w;
            }

            d = u.thickness * abs(length(p - P) - u.radius) + abs(q.z) * u.depth;
            z += d;

            float4 vol = (cos(d / 0.1 + float4(1.0, 2.0, 2.5, 0.0) + u.hue) + 1.0) / max(d, 1e-4) * z;
            float hole = smoothstep(-0.05, -0.35, length(p.xy - P.xy) - u.radius);
            float4 glow = u.glow * (cos(-u.pulse * t + D / 0.1 + float4(1.0, 2.0, 2.5, 0.0) + u.hue) + 1.0)
                * exp2(-D * D) * z;

            o += mix(vol, float4(0.0), hole) + glow;
        }

        o = o / 1e4 * u.exposure;
        o *= 1.0 - length(uv) * u.vignette;
        o = sqrt(1.0 - exp(-1.5 * o * o));
        float3 rgb = o.rgb * u.opacity * edgeFade;
        float alpha = clamp(max(max(rgb.r, rgb.g), rgb.b), 0.0, 1.0);
        // Composite the glow over a black interior, using the same ring plane
        // and inner falloff as the volume. Only the exterior reveals the desktop.
        float planeDistance = length(uv * u.camDist / u.focal) - u.radius;
        float interior = 1.0 - smoothstep(-0.35, -0.05, planeDistance);
        float interiorAlpha = interior * u.opacity * edgeFade;
        alpha += (1.0 - alpha) * interiorAlpha;
        return half4(half3(rgb), half(alpha));
    }

    vertex SpriteOut aibo_portal_sprite_vertex(
        uint vid [[vertex_id]],
        constant SpriteUniforms &u [[buffer(0)]]
    ) {
        float2 corners[4] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(1.0, 1.0),
            float2(0.0, 1.0)
        };
        uint idx[6] = { 0, 1, 2, 0, 2, 3 };
        float2 uv = corners[idx[vid]];

        float2 spritePx = max(u.charSize * max(u.scale, 0.001), float2(1.0));
        float2 pad = u.blur / spritePx;
        float2 spriteUV = uv * (1.0 + 2.0 * pad) - pad;

        float2 origin = float2(
            u.resolution.x * 0.5,
            u.resolution.y * 0.5 + u.charSize.y * 0.42
        );
        float2 local = float2(
            (spriteUV.x - 0.5) * u.charSize.x,
            (spriteUV.y - 0.92) * u.charSize.y
        );
        float2 p = origin + local * u.scale + u.offset;
        float2 ndc = (p / u.resolution) * 2.0 - 1.0;
        ndc.y *= -1.0;

        SpriteOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = spriteUV;
        out.opacity = u.opacity;
        return out;
    }

    fragment half4 aibo_portal_sprite_fragment(
        SpriteOut in [[stage_in]],
        constant SpriteUniforms &u [[buffer(0)]],
        texture2d<float> image [[texture(0)]],
        sampler imageSampler [[sampler(0)]]
    ) {
        if (u.blur < 0.5) {
            float4 tex = image.sample(imageSampler, in.uv);
            return half4(tex * in.opacity);
        }

        float2 spritePx = max(u.charSize * max(u.scale, 0.001), float2(1.0));
        float2 uvPerPx = 1.0 / spritePx;
        float sigma = max(u.blur, 0.5);
        float stepPx = (3.0 * sigma) / 4.0;
        float4 acc = float4(0.0);
        float wsum = 0.0;
        for (int y = -4; y <= 4; y++) {
            for (int x = -4; x <= 4; x++) {
                float2 offsetPx = float2(float(x), float(y)) * stepPx;
                float w = exp(-0.5 * dot(offsetPx, offsetPx) / (sigma * sigma));
                float4 tex = image.sample(imageSampler, in.uv + offsetPx * uvPerPx, level(0.0));
                acc += tex * w;
                wsum += w;
            }
        }
        return half4((acc / max(wsum, 1e-4)) * in.opacity);
    }
    """
}
