import CoreGraphics
import Foundation

/// Recovers a 1:1 texel grid from upscaled / slightly compressed pixel art.
///
/// Conservative: returns `nil` unless a regular N×N lattice reconstructs the
/// source closely. Photos and already-1px sprites stay untouched.
public enum PixelArtGridRestorer: Sendable {
    /// Mean per-channel absolute error allowed after reconstructing with N.
    public static let maximumMeanError: Double = 12
    /// Share of texels whose pixels match the majority color (delta ≤ 8).
    public static let minimumAgreement: Double = 0.88
    /// Winning color must cover this share of pixels in each tile (exact-ish lattice).
    public static let minimumMajorityShare: Double = 0.75
    public static let maximumTexelSize = 16
    public static let minimumRestoredEdge = 8

    /// Detects N and downsamples. `nil` when the image is not regular pixel art.
    public static func restore(_ image: CGImage) -> CGImage? {
        guard let texelSize = detectTexelSize(in: image) else { return nil }
        return downsample(image, texelSize: texelSize)
    }

    public static func detectTexelSize(in image: CGImage) -> Int? {
        guard let bitmap = Bitmap.copyBGRA(image) else { return nil }
        return detectTexelSize(bitmap)
    }

    public static func downsample(_ image: CGImage, texelSize: Int) -> CGImage? {
        guard texelSize >= 2, let bitmap = Bitmap.copyBGRA(image) else { return nil }
        return downsample(bitmap, texelSize: texelSize)
    }

    private static func detectTexelSize(_ bitmap: Bitmap) -> Int? {
        let maxN = min(
            maximumTexelSize,
            bitmap.width / minimumRestoredEdge,
            bitmap.height / minimumRestoredEdge
        )
        guard maxN >= 2 else { return nil }

        var bestN = 0
        var bestError = Double.greatestFiniteMagnitude
        var accepted: [(n: Int, error: Double)] = []
        accepted.reserveCapacity(maxN - 1)

        for n in 2...maxN {
            let score = score(bitmap, texelSize: n)
            guard score.opaqueTiles >= 16,
                  score.agreement >= minimumAgreement,
                  score.majorityShare >= minimumMajorityShare,
                  score.meanError <= maximumMeanError
            else { continue }
            accepted.append((n, score.meanError))
            if score.meanError < bestError {
                bestError = score.meanError
                bestN = n
            }
        }
        guard bestN >= 2 else { return nil }

        let errorCap = max(bestError * 1.3, 1)
        let largest = accepted
            .filter { $0.error <= errorCap }
            .map(\.n)
            .max()
        return largest
    }

    private static func downsample(_ bitmap: Bitmap, texelSize: Int) -> CGImage? {
        let outWidth = bitmap.width / texelSize
        let outHeight = bitmap.height / texelSize
        guard outWidth >= 1, outHeight >= 1 else { return nil }

        var pixels = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        for tileY in 0..<outHeight {
            for tileX in 0..<outWidth {
                let color = majorityColor(bitmap, tileX: tileX, tileY: tileY, texelSize: texelSize).pixel
                let offset = (tileY * outWidth + tileX) * 4
                pixels[offset] = color.blue
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.red
                pixels[offset + 3] = color.alpha
            }
        }
        return Bitmap.makeImage(pixels: pixels, width: outWidth, height: outHeight)
    }

    private static func score(_ bitmap: Bitmap, texelSize: Int) -> (
        meanError: Double,
        agreement: Double,
        majorityShare: Double,
        opaqueTiles: Int
    ) {
        let tilesX = bitmap.width / texelSize
        let tilesY = bitmap.height / texelSize
        var errorSum = 0.0
        var sampleCount = 0
        var matching = 0
        var majorityPixels = 0
        var opaqueTiles = 0

        for tileY in 0..<tilesY {
            for tileX in 0..<tilesX {
                let voted = majorityColor(bitmap, tileX: tileX, tileY: tileY, texelSize: texelSize)
                let color = voted.pixel
                majorityPixels += voted.count
                if color.alpha > 26 { opaqueTiles += 1 }
                let originX = tileX * texelSize
                let originY = tileY * texelSize
                for dy in 0..<texelSize {
                    for dx in 0..<texelSize {
                        let pixel = bitmap.pixel(x: originX + dx, y: originY + dy)
                        errorSum += Double(abs(Int(pixel.blue) - Int(color.blue)))
                            + Double(abs(Int(pixel.green) - Int(color.green)))
                            + Double(abs(Int(pixel.red) - Int(color.red)))
                            + Double(abs(Int(pixel.alpha) - Int(color.alpha)))
                        sampleCount += 1
                        if pixel.matches(color, delta: 8) { matching += 1 }
                    }
                }
            }
        }

        guard sampleCount > 0 else {
            return (
                meanError: .greatestFiniteMagnitude,
                agreement: 0,
                majorityShare: 0,
                opaqueTiles: 0
            )
        }
        return (
            meanError: errorSum / Double(sampleCount) / 4,
            agreement: Double(matching) / Double(sampleCount),
            majorityShare: Double(majorityPixels) / Double(sampleCount),
            opaqueTiles: opaqueTiles
        )
    }

    private static func majorityColor(
        _ bitmap: Bitmap,
        tileX: Int,
        tileY: Int,
        texelSize: Int
    ) -> (pixel: Bitmap.Pixel, count: Int) {
        var counts: [UInt32: (pixel: Bitmap.Pixel, count: Int)] = [:]
        counts.reserveCapacity(min(64, texelSize * texelSize))
        let originX = tileX * texelSize
        let originY = tileY * texelSize
        for dy in 0..<texelSize {
            for dx in 0..<texelSize {
                let pixel = bitmap.pixel(x: originX + dx, y: originY + dy)
                let key = pixel.quantizedKey
                if var entry = counts[key] {
                    entry.count += 1
                    counts[key] = entry
                } else {
                    counts[key] = (pixel, 1)
                }
            }
        }
        guard let winner = counts.max(by: { $0.value.count < $1.value.count })?.value else {
            return (Bitmap.Pixel(blue: 0, green: 0, red: 0, alpha: 0), 0)
        }
        if winner.pixel.alpha < 32 {
            return (Bitmap.Pixel(blue: 0, green: 0, red: 0, alpha: 0), winner.count)
        }
        if winner.pixel.alpha > 224 {
            return (
                Bitmap.Pixel(
                    blue: winner.pixel.blue,
                    green: winner.pixel.green,
                    red: winner.pixel.red,
                    alpha: 255
                ),
                winner.count
            )
        }
        return winner
    }
}

/// Integer-scale layout for pixel-art sprites (points, not backing pixels).
public enum PixelArtScale: Sendable {
    public struct Layout: Equatable, Sendable {
        public var width: Double
        public var height: Double
        /// Backing pixels per source pixel. Negative `-k` means downscale by `k`.
        /// `0` is a non-integer aspect-fit fallback.
        public var integerScale: Int

        public init(width: Double, height: Double, integerScale: Int) {
            self.width = width
            self.height = height
            self.integerScale = integerScale
        }
    }

    /// Candidate percents that produce distinct `fillWidth` sizes, labeled by
    /// the actual width relative to `baseSize` (so 150% is omitted when it
    /// snaps to the same pixels as 200%).
    public static func distinctFillWidthPercents(
        sourceWidth: Int,
        sourceHeight: Int,
        backingScale: Double,
        baseSize: Double,
        candidates: [Double]
    ) -> [Double] {
        guard sourceWidth > 0, sourceHeight > 0, backingScale > 0, baseSize > 0 else {
            return candidates
        }
        var seenWidths = Set<Int>()
        var percents: [Double] = []
        percents.reserveCapacity(candidates.count)
        for candidate in candidates {
            let layout = fillWidth(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: baseSize * candidate / 100,
                backingScale: backingScale
            )
            let widthKey = Int((layout.width * 100).rounded())
            guard seenWidths.insert(widthKey).inserted else { continue }
            percents.append(((layout.width / baseSize) * 100).rounded())
        }
        return percents
    }

    /// Nearest integer scale whose width matches `targetWidth` points; height follows aspect.
    public static func fillWidth(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Double,
        backingScale: Double
    ) -> Layout {
        guard sourceWidth > 0, sourceHeight > 0, backingScale > 0, targetWidth > 0 else {
            return Layout(width: max(targetWidth, 0), height: 0, integerScale: 0)
        }
        let fitScale = targetWidth * backingScale / Double(sourceWidth)
        return layout(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            scale: nearestScale(fitScale),
            backingScale: backingScale
        )
    }

    /// Largest integer scale that fits inside the target point box.
    public static func fit(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Double,
        targetHeight: Double,
        backingScale: Double
    ) -> Layout {
        guard sourceWidth > 0, sourceHeight > 0, backingScale > 0,
              targetWidth > 0, targetHeight > 0
        else {
            return Layout(width: max(targetWidth, 0), height: max(targetHeight, 0), integerScale: 0)
        }
        let destPxWidth = targetWidth * backingScale
        let destPxHeight = targetHeight * backingScale
        let maxUp = min(
            destPxWidth / Double(sourceWidth),
            destPxHeight / Double(sourceHeight)
        )
        if maxUp >= 1 {
            let n = max(1, Int(maxUp.rounded(.down)))
            return layout(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                scale: Double(n),
                backingScale: backingScale
            )
        }

        let needed = max(
            Double(sourceWidth) / destPxWidth,
            Double(sourceHeight) / destPxHeight
        )
        let k = max(2, Int(needed.rounded(.up)))
        return layout(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            scale: 1 / Double(k),
            backingScale: backingScale
        )
    }

    private static func nearestScale(_ fitScale: Double) -> Double {
        if fitScale >= 1 {
            return Double(max(1, Int(fitScale.rounded())))
        }
        let inverse = max(1, Int((1 / max(fitScale, 0.001)).rounded()))
        return 1 / Double(inverse)
    }

    private static func layout(
        sourceWidth: Int,
        sourceHeight: Int,
        scale: Double,
        backingScale: Double
    ) -> Layout {
        if scale >= 1 {
            let n = max(1, Int(scale.rounded()))
            return Layout(
                width: Double(n * sourceWidth) / backingScale,
                height: Double(n * sourceHeight) / backingScale,
                integerScale: n
            )
        }
        let k = max(1, Int((1 / scale).rounded()))
        let destWidth = max(1, sourceWidth / k)
        let destHeight = max(1, sourceHeight / k)
        return Layout(
            width: Double(destWidth) / backingScale,
            height: Double(destHeight) / backingScale,
            integerScale: -k
        )
    }
}

private struct Bitmap: Sendable {
    var pixels: [UInt8]
    var width: Int
    var height: Int
    var bytesPerRow: Int

    struct Pixel: Equatable {
        var blue: UInt8
        var green: UInt8
        var red: UInt8
        var alpha: UInt8

        var quantizedKey: UInt32 {
            UInt32(blue >> 2)
                | (UInt32(green >> 2) << 6)
                | (UInt32(red >> 2) << 12)
                | (UInt32(alpha >> 2) << 18)
        }

        func matches(_ other: Pixel, delta: UInt8) -> Bool {
            channelDelta(blue, other.blue) <= delta
                && channelDelta(green, other.green) <= delta
                && channelDelta(red, other.red) <= delta
                && channelDelta(alpha, other.alpha) <= delta
        }

        private func channelDelta(_ a: UInt8, _ b: UInt8) -> UInt8 {
            a > b ? a - b : b - a
        }
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let offset = y * bytesPerRow + x * 4
        return Pixel(
            blue: pixels[offset],
            green: pixels[offset + 1],
            red: pixels[offset + 2],
            alpha: pixels[offset + 3]
        )
    }

    static func copyBGRA(_ image: CGImage) -> Bitmap? {
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
        return Bitmap(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
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
            bytesPerRow: width * 4,
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
