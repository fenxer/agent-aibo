import AppKit
import Metal
import QuartzCore

/// On-demand Metal renderer for the aibo-switch wipe.
///
/// Compiles the Shadertoy port at first use (`MTLDevice.makeLibrary(source:)`) so
/// the app target does not need a compiled `.metal` file. Frames are drawn by
/// a short-lived display link on `AiboSwitchMetalView` — not by SwiftUI.
@MainActor
final class AiboSwitchRenderer {
    static let shared: AiboSwitchRenderer? = AiboSwitchRenderer()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: MTLCompileOptions())
        } catch {
            #if DEBUG
            print("AiboSwitchRenderer: shader compile failed: \(error)")
            #endif
            return nil
        }
        guard let vertex = library.makeFunction(name: "aibo_switch_vertex"),
              let fragment = library.makeFunction(name: "aibo_switch_fragment")
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

        let samplerDescriptor = MTLSamplerDescriptor()
        // Match AiboSpriteLayer's nearest filters so the first/last morph
        // frame doesn't soften then snap back to the live sprite.
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.sampler = sampler
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
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
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
        from: MTLTexture,
        to: MTLTexture,
        progress: Float
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
        encoder.setRenderPipelineState(pipeline)
        var progressValue = progress
        encoder.setFragmentBytes(&progressValue, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentTexture(from, index: 0)
        encoder.setFragmentTexture(to, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension AiboSwitchRenderer {
    /// Shadertoy mask-warp: cubicInOut, mirror-wrapped UV offset by a noise mask,
    /// mix(from, to, S(mask - progress)). iChannel0 is value-noise (only two
    /// images are bound — outgoing and incoming).
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut aibo_switch_vertex(uint vid [[vertex_id]]) {
        float2 pos = float2((vid << 1) & 2, vid & 2);
        VertexOut out;
        out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
        // Metal clip Y is up; SwiftUI's NSHostingView is flipped (Y down).
        out.uv = float2(pos.x, 1.0 - pos.y);
        return out;
    }

    float aibo_glslMod(float x, float y) {
        return x - y * floor(x / y);
    }

    float2 aibo_glslMod(float2 x, float y) {
        return x - y * floor(x / y);
    }

    float2 aibo_mirror(float2 v) {
        float2 m = aibo_glslMod(v, 2.0);
        return mix(m, 2.0 - m, step(1.0, m));
    }

    float aibo_cubicInOut(float t) {
        t = clamp(t, 0.0, 1.0);
        if (t < 0.5) {
            return 4.0 * t * t * t;
        }
        float u = 2.0 * t - 2.0;
        return 0.5 * u * u * u + 1.0;
    }

    float aibo_hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float aibo_valueNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = aibo_hash21(i);
        float b = aibo_hash21(i + float2(1.0, 0.0));
        float c = aibo_hash21(i + float2(0.0, 1.0));
        float d = aibo_hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    float aibo_mask(float2 uv) {
        // Base frequency 12 (was 4): ~96pt desktop pets only covered a few
        // coarse blobs, so the wipe read as a plain slide unless you stared.
        float2 p = uv * 12.0;
        float value = 0.0;
        float amplitude = 0.5;
        value += amplitude * aibo_valueNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
        value += amplitude * aibo_valueNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
        value += amplitude * aibo_valueNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
        value += amplitude * aibo_valueNoise(p);
        return clamp(value, 0.0, 1.0);
    }

    fragment half4 aibo_switch_fragment(
        VertexOut in [[stage_in]],
        constant float &progress [[buffer(0)]],
        texture2d<half> fromTexture [[texture(0)]],
        texture2d<half> toTexture [[texture(1)]],
        sampler textureSampler [[sampler(0)]]
    ) {
        float p = aibo_cubicInOut(progress);
        float mask = aibo_mask(in.uv);
        float2 fromUV = aibo_mirror(float2(in.uv.x + p * mask, in.uv.y));
        float2 toUV = aibo_mirror(float2(in.uv.x - (1.0 - p) * mask, in.uv.y));
        half4 fromColor = fromTexture.sample(textureSampler, fromUV);
        half4 toColor = toTexture.sample(textureSampler, toUV);
        float aa = max(1.5 * fwidth(mask - p), 0.002);
        // Drive the wipe from below 0 to above 1 so progress 0 is a still of
        // `from` and progress 1 is a still of `to`, even where the noise mask
        // is near 0 (otherwise some pets flash the incoming image in place).
        float threshold = mix(-aa, 1.0 + aa, p);
        float stepMask = smoothstep(0.0, aa, mask - threshold);
        return mix(toColor, fromColor, half(stepMask));
    }
    """
}
