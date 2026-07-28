import AppKit
import SwiftUI

/// Visual constants derived from the pet artwork.
enum PetAppearance {
    /// Pow `.movingParts.vanish` default timing.
    static let vanishAnimation: Animation = .easeOut(duration: 0.9)
    static let vanishDuration: Duration = .milliseconds(900)

    /// Drop-in spring for show. Intentionally not Pow `.boing` — that GeometryEffect
    /// makes NSHostingView rewrite PetPanel's content size (width→0) and crash.
    static let boingAnimation: Animation = .interpolatingSpring(stiffness: 220, damping: 14)

    /// Dominant opaque color of `DefaultPet` (cached once).
    static let dominantColor: Color = Color(nsColor: dominantNSColor)

    private static let dominantNSColor: NSColor = {
        guard let image = NSImage(named: "DefaultPet"),
              let color = DominantColorSampler.sample(from: image)
        else {
            return .systemPink
        }
        return color
    }()
}

/// Histogram-based dominant color from opaque sprite pixels.
enum DominantColorSampler {
    static func sample(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 4 bits/channel → 4096 buckets; skip clear + near-black outline.
        var counts: [Int: Int] = [:]
        let alphaThreshold: UInt8 = 26
        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = rgba[offset + 3]
            guard alpha > alphaThreshold else { continue }

            let red = rgba[offset]
            let green = rgba[offset + 1]
            let blue = rgba[offset + 2]
            if red < 30, green < 30, blue < 30 { continue }

            let key = ((Int(red) >> 4) << 8) | ((Int(green) >> 4) << 4) | (Int(blue) >> 4)
            counts[key, default: 0] += 1
        }

        guard let bestKey = counts.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        let redQ = (bestKey >> 8) & 0xF
        let greenQ = (bestKey >> 4) & 0xF
        let blueQ = bestKey & 0xF
        return NSColor(
            srgbRed: CGFloat(redQ * 16 + 8) / 255,
            green: CGFloat(greenQ * 16 + 8) / 255,
            blue: CGFloat(blueQ * 16 + 8) / 255,
            alpha: 1
        )
    }
}
