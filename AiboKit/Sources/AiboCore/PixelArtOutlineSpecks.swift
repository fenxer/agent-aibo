import CoreGraphics
import Foundation

/// Recolors isolated outline-ring outliers onto the detected stroke color.
///
/// Skips the whole image unless the opaque silhouette ring is dominated by one
/// color (black or colored). Never touches interior pixels.
public enum PixelArtOutlineSpecks: Sendable {
    public static let minimumRingCount = 16
    public static let minimumStrokeShare = 0.75
    public static let strokeMatchDelta = 30
    public static let outlierDelta = 48
    public static let maximumSpeckSize = 2

    public static func remove(_ image: CGImage) -> CGImage? {
        guard var bitmap = Bitmap.copy(image) else { return nil }
        guard apply(&bitmap) else { return image }
        return bitmap.makeImage()
    }

    private static func apply(_ bitmap: inout Bitmap) -> Bool {
        let width = bitmap.width
        let height = bitmap.height
        guard width > 2, height > 2 else { return false }

        var ring: [Int] = []
        ring.reserveCapacity(width + height)
        var isRing = [Bool](repeating: false, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                guard bitmap.isOpaque(x: x, y: y) else { continue }
                guard hasTransparentNeighbor(bitmap, x: x, y: y) else { continue }
                let index = y * width + x
                isRing[index] = true
                ring.append(index)
            }
        }
        guard ring.count >= minimumRingCount else { return false }

        var bucketCounts: [UInt32: Int] = [:]
        var bucketColor: [UInt32: Pixel] = [:]
        for index in ring {
            let pixel = bitmap.pixel(at: index)
            let key = pixel.quantizedKey
            bucketCounts[key, default: 0] += 1
            if bucketColor[key] == nil { bucketColor[key] = pixel }
        }
        guard let winner = bucketCounts.max(by: { $0.value < $1.value }) else { return false }
        let strokeShare = Double(winner.value) / Double(ring.count)
        guard strokeShare >= minimumStrokeShare, let stroke = bucketColor[winner.key] else {
            return false
        }

        var interiorByKey: [UInt32: Int] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard bitmap.isOpaque(x: x, y: y), !isRing[index] else { continue }
                interiorByKey[bitmap.pixel(at: index).quantizedKey, default: 0] += 1
            }
        }

        var visited = [Bool](repeating: false, count: width * height)
        var changed = false
        for start in ring {
            guard !visited[start] else { continue }
            let startPixel = bitmap.pixel(at: start)
            guard startPixel.distance(to: stroke) > outlierDelta else {
                visited[start] = true
                continue
            }

            let component = floodOutliers(
                from: start,
                bitmap: bitmap,
                isRing: isRing,
                stroke: stroke,
                visited: &visited
            )
            guard (1...maximumSpeckSize).contains(component.count) else { continue }
            guard interiorByKey[startPixel.quantizedKey, default: 0] == 0 else { continue }

            let touchesStroke = component.contains { index in
                let x = index % width
                let y = index / width
                return hasStrokeNeighbor(bitmap, x: x, y: y, stroke: stroke)
            }
            guard touchesStroke else { continue }

            for index in component {
                bitmap.setPixel(stroke, at: index)
            }
            changed = true
        }
        return changed
    }

    private static func hasTransparentNeighbor(_ bitmap: Bitmap, x: Int, y: Int) -> Bool {
        neighbors4.contains { nx, ny in
            !bitmap.isOpaque(x: x + nx, y: y + ny)
        }
    }

    private static func hasStrokeNeighbor(
        _ bitmap: Bitmap,
        x: Int,
        y: Int,
        stroke: Pixel
    ) -> Bool {
        neighbors8.contains { nx, ny in
            let px = x + nx
            let py = y + ny
            guard bitmap.isOpaque(x: px, y: py) else { return false }
            return bitmap.pixel(x: px, y: py).distance(to: stroke) <= strokeMatchDelta
        }
    }

    private static func floodOutliers(
        from start: Int,
        bitmap: Bitmap,
        isRing: [Bool],
        stroke: Pixel,
        visited: inout [Bool]
    ) -> [Int] {
        let width = bitmap.width
        let height = bitmap.height
        var stack = [start]
        var component: [Int] = []
        visited[start] = true
        while let index = stack.popLast() {
            component.append(index)
            let x = index % width
            let y = index / width
            for (dx, dy) in neighbors8 {
                let nx = x + dx
                let ny = y + dy
                guard (0..<width).contains(nx), (0..<height).contains(ny) else { continue }
                let next = ny * width + nx
                guard !visited[next], isRing[next] else { continue }
                let pixel = bitmap.pixel(at: next)
                guard pixel.distance(to: stroke) > outlierDelta else { continue }
                visited[next] = true
                stack.append(next)
            }
        }
        return component
    }

    private static let neighbors4 = [(0, -1), (0, 1), (-1, 0), (1, 0)]
    private static let neighbors8 = [
        (0, -1), (0, 1), (-1, 0), (1, 0),
        (-1, -1), (1, -1), (-1, 1), (1, 1),
    ]
}

private struct Pixel: Equatable {
    var blue: UInt8
    var green: UInt8
    var red: UInt8
    var alpha: UInt8

    var quantizedKey: UInt32 {
        UInt32(blue >> 3)
            | (UInt32(green >> 3) << 5)
            | (UInt32(red >> 3) << 10)
            | (UInt32(alpha >> 3) << 15)
    }

    func distance(to other: Pixel) -> Int {
        abs(Int(blue) - Int(other.blue))
            + abs(Int(green) - Int(other.green))
            + abs(Int(red) - Int(other.red))
    }
}

private struct Bitmap {
    var pixels: [UInt8]
    var width: Int
    var height: Int
    var bytesPerRow: Int

    func isOpaque(x: Int, y: Int) -> Bool {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return false }
        return pixels[y * bytesPerRow + x * 4 + 3] >= 128
    }

    func pixel(x: Int, y: Int) -> Pixel {
        pixel(at: y * width + x)
    }

    func pixel(at index: Int) -> Pixel {
        let x = index % width
        let y = index / width
        let offset = y * bytesPerRow + x * 4
        return Pixel(
            blue: pixels[offset],
            green: pixels[offset + 1],
            red: pixels[offset + 2],
            alpha: pixels[offset + 3]
        )
    }

    mutating func setPixel(_ pixel: Pixel, at index: Int) {
        let x = index % width
        let y = index / width
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = pixel.blue
        pixels[offset + 1] = pixel.green
        pixels[offset + 2] = pixel.red
        pixels[offset + 3] = pixel.alpha
    }

    static func copy(_ image: CGImage) -> Bitmap? {
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

    func makeImage() -> CGImage? {
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
