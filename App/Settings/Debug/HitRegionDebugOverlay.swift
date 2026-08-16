#if DEBUG
import AppKit

/// Semi-transparent fills for AiboPanel hit-testing regions (Development toggle).
/// Never participates in hit testing itself.
final class HitRegionDebugOverlay: NSView {
    var aiboHitRect: CGRect = .null {
        didSet { needsDisplay = true }
    }

    var contentInsets: AiboContentInsets = .current(musicNotesEnabled: false) {
        didSet { needsDisplay = true }
    }

    /// Approximate bubble stack rects (bottom-left); should accept clicks.
    var bubbleHitRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    /// Green where alpha mask is opaque (actual drag target); clear elsewhere in pet square.
    var opaqueAiboImage: NSImage? {
        didSet { needsDisplay = true }
    }

    var isOverlayEnabled = false {
        didSet {
            isHidden = !isOverlayEnabled
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard isOverlayEnabled else { return }

        let panel = bounds
        // Full panel frame — anything that can still steal clicks if hitTest is wrong.
        NSColor.systemPurple.withAlphaComponent(0.12).setFill()
        panel.fill()

        let insets = contentInsets
        let base = AiboContentInsets.base
        let musicTop = max(0, insets.top - base)
        let musicTrailing = max(0, insets.trailing - base)

        // Base padding ring (8pt).
        NSColor.systemOrange.withAlphaComponent(0.28).setFill()
        // bottom
        NSRect(x: 0, y: 0, width: panel.width, height: insets.bottom).fill()
        // leading
        NSRect(x: 0, y: 0, width: insets.leading, height: panel.height).fill()
        // top base only (below music overflow)
        if insets.top > 0 {
            let topBaseHeight = min(base, insets.top)
            NSRect(
                x: 0,
                y: panel.height - topBaseHeight,
                width: panel.width,
                height: topBaseHeight
            ).fill()
        }
        // trailing base only (inside music overflow)
        if insets.trailing > 0 {
            let trailingBaseWidth = min(base, insets.trailing)
            NSRect(
                x: panel.width - trailingBaseWidth,
                y: 0,
                width: trailingBaseWidth,
                height: panel.height
            ).fill()
        }

        // Music-note overflow (extra top / trailing) — should be click-through.
        NSColor.systemYellow.withAlphaComponent(0.38).setFill()
        if musicTop > 0 {
            NSRect(
                x: 0,
                y: panel.height - insets.top,
                width: panel.width,
                height: musicTop
            ).fill()
        }
        if musicTrailing > 0 {
            NSRect(
                x: panel.width - insets.trailing,
                y: 0,
                width: musicTrailing,
                height: panel.height - (musicTop > 0 ? insets.top : 0)
            ).fill()
        }

        // aiboHitRect square (alpha-tested region).
        if aiboHitRect.isNull == false, aiboHitRect.width > 0, aiboHitRect.height > 0 {
            NSColor.systemBlue.withAlphaComponent(0.22).setFill()
            aiboHitRect.fill()
            NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
            let path = NSBezierPath(rect: aiboHitRect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()

            if let opaqueAiboImage {
                opaqueAiboImage.draw(
                    in: aiboHitRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        }

        // Bubble hit unions — cyan; empty purple outside these should pass through.
        NSColor.systemCyan.withAlphaComponent(0.28).setFill()
        NSColor.systemCyan.withAlphaComponent(0.9).setStroke()
        for rect in bubbleHitRects where rect.width > 0 && rect.height > 0 {
            rect.fill()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }

        drawLegend()
    }

    private func drawLegend() {
        let lines: [(String, NSColor)] = [
            ("panel", .systemPurple),
            ("base pad", .systemOrange),
            ("music overflow", .systemYellow),
            ("aiboHitRect", .systemBlue),
            ("opaque = drag", .systemGreen),
            ("bubble hit", .systemCyan),
        ]
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        var y = bounds.height - 14
        for (label, color) in lines {
            let swatch = NSRect(x: 6, y: y - 2, width: 8, height: 8)
            color.withAlphaComponent(0.75).setFill()
            swatch.fill()
            let text = NSAttributedString(
                string: label,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .strokeColor: NSColor.black.withAlphaComponent(0.7),
                    .strokeWidth: -2,
                ]
            )
            text.draw(at: NSPoint(x: 18, y: y - 4))
            y -= 12
        }
    }
}
#endif
