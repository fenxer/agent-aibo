import AppKit
import SwiftUI

/// Hosts SwiftUI content and only accepts hits on opaque pet pixels.
///
/// macOS 27's Swift AppKit overlay no longer exposes `NSWindow.hitTest`, so click-through
/// lives on the content view. The alpha mask is built once from the pet image.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    private let opaqueAlphaThreshold: UInt8 = 26 // ~10%
    private let hitTestImage: NSImage?
    private var alphaMask: AlphaMask?

    /// Bottom-centered rect used for pet-image alpha hit testing (window coordinates of content view).
    var petHitRect: CGRect = .null

    init(rootView: Content, hitTestImage: NSImage?) {
        self.hitTestImage = hitTestImage
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("Use init(rootView:hitTestImage:)")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }

        if petHitRect.isNull == false, petHitRect.contains(point) {
            if alphaMask == nil {
                alphaMask = hitTestImage.flatMap(AlphaMask.init)
            }
            if let alphaMask {
                let local = CGPoint(x: point.x - petHitRect.minX, y: point.y - petHitRect.minY)
                let localBounds = CGRect(origin: .zero, size: petHitRect.size)
                guard alphaMask.isOpaque(at: local, in: localBounds, threshold: opaqueAlphaThreshold) else {
                    return nil
                }
            }
        } else if petHitRect.isNull == false {
            // Outside the pet sprite: allow hits only when SwiftUI has content there (e.g. bubble).
            return super.hitTest(point)
        }

        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Drag the panel only from opaque pet pixels; bubbles need SwiftUI taps
        // (e.g. dismiss `.failed`).
        if isOpaquePetHit(at: point) {
            window?.performDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    private func isOpaquePetHit(at point: NSPoint) -> Bool {
        guard petHitRect.isNull == false, petHitRect.contains(point) else { return false }
        if alphaMask == nil {
            alphaMask = hitTestImage.flatMap(AlphaMask.init)
        }
        guard let alphaMask else { return true }
        let local = CGPoint(x: point.x - petHitRect.minX, y: point.y - petHitRect.minY)
        let localBounds = CGRect(origin: .zero, size: petHitRect.size)
        return alphaMask.isOpaque(at: local, in: localBounds, threshold: opaqueAlphaThreshold)
    }
}

/// Cached alpha channel sampled in image pixel space.
private struct AlphaMask: Sendable {
    private let width: Int
    private let height: Int
    private let alphas: [UInt8]

    init?(image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        width = cgImage.width
        height = cgImage.height
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

        var alphas = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alphas[index] = rgba[index * 4 + 3]
        }
        self.alphas = alphas
    }

    func isOpaque(at point: NSPoint, in bounds: NSRect, threshold: UInt8) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }

        let x = Int((point.x / bounds.width) * CGFloat(width))
        // AppKit view Y grows upward; CG bitmap Y grows downward.
        let yFromTop = Int(((bounds.height - point.y) / bounds.height) * CGFloat(height))

        guard x >= 0, yFromTop >= 0, x < width, yFromTop < height else { return false }
        return alphas[yFromTop * width + x] > threshold
    }
}
