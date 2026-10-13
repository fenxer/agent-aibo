import AppKit
import SwiftUI

/// Hosts SwiftUI content and only accepts hits on opaque pet pixels / bubbles.
///
/// macOS 27's Swift AppKit overlay no longer exposes `NSWindow.hitTest`, so click-through
/// lives on the content view. The alpha mask is built once from the aibo image.
///
/// `aiboHitRect` / `bubbleHitRects` use bottom-left coordinates (same as the panel).
/// `measuredBubbleHitRects` use this view's coordinates (top-left, same as SwiftUI).
/// `NSHostingView` is flipped (origin top-left), so hit-test points are converted first.
enum AiboPanelSpace {
    static let name = "aiboPanel"
}

final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    private let opaqueAlphaThreshold: UInt8 = 26 // ~10%
    private var alphaMask: AlphaMask?

    /// Pet sprite square in bottom-left content coordinates.
    var aiboHitRect: CGRect = .null
    /// Approximate bubble stack rects in bottom-left content coordinates.
    var bubbleHitRects: [CGRect] = []
    /// Plugin card frames in this view's top-left coordinates.
    /// Estimates in `bubbleHitRects` miss buttons once a card is taller than the guess.
    var measuredBubbleHitRects: [CGRect] = []

    init(rootView: Content, hitTestImage: NSImage?) {
        self.alphaMask = Self.makeAlphaMask(from: hitTestImage)
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard dropOperation(sender) != [], let url = Self.droppedFileURL(sender) else { return false }
        ExtensionCenter.shared.receiveDroppedFile(url)
        return true
    }

    /// Only the opaque pet, and only a file some enabled plugin listed in `accepts`.
    private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        guard isOpaquePetHit(at: point), let url = Self.droppedFileURL(sender) else { return [] }
        return ExtensionCenter.shared.canAcceptDroppedFile(url) ? .copy : []
    }

    private static func droppedFileURL(_ sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first { ExtensionCenter.shared.canAcceptDroppedFile($0) } ?? urls?.first
    }

    func updateHitTestImage(_ image: NSImage?) {
        alphaMask = Self.makeAlphaMask(from: image)
    }

    /// Green where pet pixels are considered opaque for drag / hit testing.
    func opaqueAiboDebugImage(size: CGSize) -> NSImage? {
        alphaMask?.tintedOpaqueImage(
            size: size,
            threshold: opaqueAlphaThreshold,
            color: NSColor.systemGreen.withAlphaComponent(0.55)
        )
    }

    private static func makeAlphaMask(from image: NSImage?) -> AlphaMask? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return AlphaMask(cgImage: cgImage)
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
        PromptFieldTracker.host = self
        // The field's SwiftUI frame, not the view AppKit would hit. A hook
        // bubble under the card makes the ancestor miss, and its tap gesture
        // then keeps the caret at the end of the text.
        if let text = PromptFieldTracker.textView(at: point) {
            return text
        }
        let p = pointInBottomLeft(point)

        if aiboHitRect.isNull == false, aiboHitRect.contains(p) {
            let opaque: Bool
            if let alphaMask {
                let local = CGPoint(x: p.x - aiboHitRect.minX, y: p.y - aiboHitRect.minY)
                let localBounds = CGRect(origin: .zero, size: aiboHitRect.size)
                opaque = alphaMask.isOpaque(at: local, in: localBounds, threshold: opaqueAlphaThreshold)
            } else {
                opaque = true
            }
            if opaque {
                // Opaque pet pixel — accept (SwiftUI context menu / AppKit drag).
                return super.hitTest(point) ?? self
            }
            // Transparent corner of the pet's box. A bubble in that square
            // still needs the click; otherwise fall through to the desktop.
        }

        // A plugin card reports where it was actually drawn. That rect wins over
        // the height estimate, which is only used to size the panel.
        // Beside a hook bubble the card is drawn in an overlay past the anchor's
        // bounds, so AppKit's hit walk stops at that ancestor and the click never
        // reaches the field. Search descendants anyway.
        if measuredBubbleHitRects.contains(where: { $0.contains(point) }) {
            return super.hitTest(point) ?? deepestDescendant(containing: point) ?? self
        }

        // Bubbles only — empty padding / music overflow / infinity frames pass through.
        if bubbleHitRects.contains(where: { $0.contains(p) }) {
            return super.hitTest(point)
        }

        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Control-click is the classic context-menu gesture; don't steal it for dragging.
        if event.modifierFlags.contains(.control) {
            if handleBubbleInspect(at: point) { return }
            super.mouseDown(with: event)
            return
        }
        // Drag the panel only from opaque pet pixels; bubbles need SwiftUI taps
        // (e.g. dismiss `.failed`).
        if isOpaquePetHit(at: point) {
            AiboPanelController.shared.performPetDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleBubbleInspect(at: point) { return }
        super.rightMouseDown(with: event)
    }

    /// SwiftUI hosting often drops wheel events before they reach an embedded
    /// `NSScrollView` (inspect JSON). Forward when the hit is inside a scroller.
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(point) {
            var view: NSView? = hit
            while let current = view {
                if let scroll = current as? NSScrollView {
                    scroll.scrollWheel(with: event)
                    return
                }
                if let scroll = current.enclosingScrollView {
                    scroll.scrollWheel(with: event)
                    return
                }
                view = current.superview
            }
        }
        super.scrollWheel(with: event)
    }

    /// Deepest visible descendant whose own bounds contain `point`, even when an
    /// ancestor's bounds do not. `point` is in this view's coordinates.
    private func deepestDescendant(containing point: NSPoint) -> NSView? {
        func walk(_ view: NSView, pointInView: NSPoint) -> NSView? {
            for subview in view.subviews.reversed() {
                guard subview.isHidden == false, subview.alphaValue > 0.01 else { continue }
                let local = view.convert(pointInView, to: subview)
                if let found = walk(subview, pointInView: local) {
                    return found
                }
            }
            if view !== self, view.bounds.contains(pointInView) {
                return view
            }
            return nil
        }
        return walk(self, pointInView: point)
    }

    /// Consume bubble right-clicks here so SwiftUI never tries to key the panel.
    @discardableResult
    private func handleBubbleInspect(at point: NSPoint) -> Bool {
        AiboPanelController.shared.handleBubbleRightClick(atBottomLeft: pointInBottomLeft(point))
    }

    private func isOpaquePetHit(at point: NSPoint) -> Bool {
        let p = pointInBottomLeft(point)
        guard aiboHitRect.isNull == false, aiboHitRect.contains(p) else { return false }
        guard let alphaMask else { return true }
        let local = CGPoint(x: p.x - aiboHitRect.minX, y: p.y - aiboHitRect.minY)
        let localBounds = CGRect(origin: .zero, size: aiboHitRect.size)
        return alphaMask.isOpaque(at: local, in: localBounds, threshold: opaqueAlphaThreshold)
    }

    /// `NSHostingView` is flipped; stored hit rects use panel bottom-left coords.
    private func pointInBottomLeft(_ point: NSPoint) -> NSPoint {
        guard isFlipped else { return point }
        return NSPoint(x: point.x, y: bounds.height - point.y)
    }
}

/// Cached alpha channel sampled in image pixel space.
/// Built on the main actor; read from AppKit hit-testing (`nonisolated`).
nonisolated private struct AlphaMask: Sendable {
    private let width: Int
    private let height: Int
    private let alphas: [UInt8]

    init?(cgImage: CGImage) {
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
        // Bottom-left local Y → CG bitmap Y (top-down).
        let yFromTop = Int(((bounds.height - point.y) / bounds.height) * CGFloat(height))

        guard x >= 0, yFromTop >= 0, x < width, yFromTop < height else { return false }
        return alphas[yFromTop * width + x] > threshold
    }

    func tintedOpaqueImage(size: CGSize, threshold: UInt8, color: NSColor) -> NSImage? {
        let pixelWidth = max(1, Int(size.width.rounded(.up)))
        let pixelHeight = max(1, Int(size.height.rounded(.up)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ), let pixels = rep.bitmapData else {
            return nil
        }

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let red = UInt8(min(max(r * 255, 0), 255))
        let green = UInt8(min(max(g * 255, 0), 255))
        let blue = UInt8(min(max(b * 255, 0), 255))
        let alpha = UInt8(min(max(a * 255, 0), 255))

        for py in 0..<pixelHeight {
            for px in 0..<pixelWidth {
                let sampleX = Int((CGFloat(px) + 0.5) / CGFloat(pixelWidth) * CGFloat(width))
                let sampleY = Int((CGFloat(py) + 0.5) / CGFloat(pixelHeight) * CGFloat(height))
                let offset = (py * pixelWidth + px) * 4
                guard sampleX >= 0, sampleY >= 0, sampleX < width, sampleY < height,
                      alphas[sampleY * width + sampleX] > threshold
                else {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                    continue
                }
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue
                pixels[offset + 3] = alpha
            }
        }

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
