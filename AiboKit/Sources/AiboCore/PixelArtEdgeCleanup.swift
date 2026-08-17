import CoreGraphics
import Foundation

/// Hardens pixel-art edges: WebP / bilinear fringes become fully clear or solid.
///
/// Runs in memory when Pixel Optimization is on. Does not write a second clip.
public enum PixelArtEdgeCleanup: Sendable {
    /// Alpha below this becomes 0; at or above becomes 255.
    public static let alphaCutoff: UInt8 = 128

    public static func clean(_ image: CGImage) -> CGImage? {
        guard let bitmap = copyBGRA(image) else { return nil }
        var pixels = bitmap.pixels
        let width = bitmap.width
        let height = bitmap.height
        let bytesPerRow = bitmap.bytesPerRow

        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let offset = row + x * 4
                let blue = pixels[offset]
                let green = pixels[offset + 1]
                let red = pixels[offset + 2]
                let alpha = pixels[offset + 3]

                if alpha == 0 {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    continue
                }
                if alpha == 255 {
                    continue
                }
                if alpha < alphaCutoff {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                    continue
                }

                let unpremultiplied = unpremultiply(red: red, green: green, blue: blue, alpha: alpha)
                pixels[offset] = quantizeFringe(unpremultiplied.blue)
                pixels[offset + 1] = quantizeFringe(unpremultiplied.green)
                pixels[offset + 2] = quantizeFringe(unpremultiplied.red)
                pixels[offset + 3] = 255
            }
        }
        return makeBGRAImage(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    /// Former semi-transparent fringe only: 6-bit snap kills WebP ringing.
    private static func quantizeFringe(_ channel: UInt8) -> UInt8 {
        channel & 0xFC
    }

    private static func unpremultiply(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8
    ) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let scale = 255.0 / Double(alpha)
        return (
            red: UInt8(min(255, (Double(red) * scale).rounded())),
            green: UInt8(min(255, (Double(green) * scale).rounded())),
            blue: UInt8(min(255, (Double(blue) * scale).rounded()))
        )
    }

    private static func copyBGRA(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let copied = context.makeImage(),
              let provider = copied.dataProvider,
              let data = provider.data,
              let pointer = CFDataGetBytePtr(data)
        else { return nil }
        let bytesPerRow = copied.bytesPerRow
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            base.copyMemory(from: pointer, byteCount: bytesPerRow * height)
        }
        return (pixels, width, height, bytesPerRow)
    }

    private static func makeBGRAImage(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> CGImage? {
        let data = pixels.withUnsafeBytes { buffer in
            Data(buffer.bindMemory(to: UInt8.self))
        } as CFData
        guard let provider = CGDataProvider(data: data),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
