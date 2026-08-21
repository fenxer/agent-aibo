import AiboCore
import AppKit
import SwiftUI

/// Visual constants derived from the aibo artwork.
@MainActor
enum AiboAppearance {
    /// Pow `.movingParts.vanish` default timing.
    static let vanishAnimation: Animation = .easeOut(duration: 0.9)
    static let vanishDuration: Duration = .milliseconds(900)

    /// Drop-in spring for show. Intentionally not Pow `.boing` — that GeometryEffect
    /// makes NSHostingView rewrite AiboPanel's content size (width→0) and crash.
    static let boingAnimation: Animation = .interpolatingSpring(stiffness: 220, damping: 14)

    private static var dominantColorCache: [String: Color] = [:]

    /// Dominant opaque color of the current aibo artwork (cached per aibo id).
    static func dominantColor(for record: AiboLibraryRecord) -> Color {
        if let cached = dominantColorCache[record.id] { return cached }
        let image = AiboSpriteCache.shared.previewImage(for: record)
        let nsColor = image.flatMap(DominantColorSampler.sample) ?? .systemPink
        let color = Color(nsColor: nsColor)
        dominantColorCache[record.id] = color
        return color
    }

    static func invalidateDominantColorCache() {
        dominantColorCache.removeAll()
    }
}

/// Padding around aibo content; grows NE when music notes are enabled so rising notes aren't clipped.
struct AiboContentInsets: Equatable, Sendable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static let base: CGFloat = 8
    /// Matches Pow rise canvas (~80 top / ~40 side) plus a little travel room.
    static let musicOverflowTop: CGFloat = 72
    static let musicOverflowTrailing: CGFloat = 48

    static func current(musicNotesEnabled: Bool) -> Self {
        if musicNotesEnabled {
            return Self(
                top: base + musicOverflowTop,
                leading: base,
                bottom: base,
                trailing: base + musicOverflowTrailing
            )
        }
        return Self(top: base, leading: base, bottom: base, trailing: base)
    }

    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }

    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
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
