import AppKit
import Metal
import QuartzCore
import SwiftUI

/// Full-bleed plasma fill behind the Codex TODO capsule contents.
///
/// Driven by a screen `CADisplayLink` only while this view is in a window —
/// the floating Aibo panel is often non-key, so `NSView.displayLink` can stall.
struct CapsulePlanShaderBackground: NSViewRepresentable {
    var progress: Double
    var track: Color

    func makeNSView(context: Context) -> CapsulePlanMetalView {
        CapsulePlanMetalView()
    }

    func updateNSView(_ view: CapsulePlanMetalView, context: Context) {
        view.updateProgress(Float(progress))
        view.trackColor = CapsulePlanShaderStyle.simdColor(from: NSColor(track))
    }
}

final class CapsulePlanMetalView: NSView {
    var trackColor: SIMD3<Float> = .zero {
        didSet { if trackColor != oldValue { drawCurrent() } }
    }

    private let tickProxy = TickProxy()
    private let metalLayer = CAMetalLayer()
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0

    /// First `updateProgress` snaps (bubble just appeared). Later changes ease.
    private var hasReceivedProgress = false
    private var displayedProgress: Float = 0
    private var progressFrom: Float = 0
    private var progressTo: Float = 0
    private var progressAnimStartedAt: CFTimeInterval = 0
    private var progressAnimDuration: CFTimeInterval = 0

    /// A 1/3 step (~0.33 of the bar) takes about half a second.
    private static let fullBarSeconds: CFTimeInterval = 1.5
    private static let minProgressSeconds: CFTimeInterval = 0.32
    private static let maxProgressSeconds: CFTimeInterval = 0.85

    private final class TickProxy: NSObject {
        weak var owner: CapsulePlanMetalView?
        @objc func tick(_ link: CADisplayLink) {
            owner?.handleTick()
        }
    }

    init() {
        super.init(frame: .zero)
        tickProxy.owner = self
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        CapsulePlanShaderRenderer.shared?.configure(metalLayer)
        layer = metalLayer
        startedAt = CACurrentMediaTime()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CapsulePlanMetalView is not loadable from a nib")
    }

    deinit {
        displayLink?.invalidate()
    }

    override var isOpaque: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
        drawCurrent()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateDrawableSize()
            startLink()
            drawCurrent()
        } else {
            stopLink()
        }
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
        drawCurrent()
    }

    func updateProgress(_ value: Float) {
        let clamped = max(0, min(1, value))
        if !hasReceivedProgress {
            hasReceivedProgress = true
            displayedProgress = clamped
            progressFrom = clamped
            progressTo = clamped
            progressAnimDuration = 0
            drawCurrent()
            return
        }
        guard abs(clamped - progressTo) > 0.0005 else { return }
        if displayLink == nil {
            displayedProgress = clamped
            progressFrom = clamped
            progressTo = clamped
            progressAnimDuration = 0
            drawCurrent()
            return
        }
        progressFrom = displayedProgress
        progressTo = clamped
        progressAnimStartedAt = CACurrentMediaTime()
        let delta = CFTimeInterval(abs(progressTo - progressFrom))
        progressAnimDuration = min(
            Self.maxProgressSeconds,
            max(Self.minProgressSeconds, delta * Self.fullBarSeconds)
        )
    }

    private func startLink() {
        stopLink()
        guard window != nil, CapsulePlanShaderRenderer.shared != nil else { return }
        let link = (window?.screen ?? NSScreen.main)?.displayLink(
            target: tickProxy,
            selector: #selector(TickProxy.tick(_:))
        ) ?? displayLink(target: tickProxy, selector: #selector(TickProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func handleTick() {
        advanceDisplayedProgress()
        drawCurrent()
    }

    private func advanceDisplayedProgress() {
        guard progressAnimDuration > 0 else { return }
        let elapsed = CACurrentMediaTime() - progressAnimStartedAt
        let linear = min(max(elapsed / progressAnimDuration, 0), 1)
        let eased = Self.cubicInOut(linear)
        displayedProgress = progressFrom + Float(eased) * (progressTo - progressFrom)
        if linear >= 1 {
            displayedProgress = progressTo
            progressAnimDuration = 0
        }
    }

    private static func cubicInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        }
        let u = -2 * t + 2
        return 1 - (u * u * u) / 2
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let width = max(1, bounds.width * scale)
        let height = max(1, bounds.height * scale)
        metalLayer.drawableSize = CGSize(width: width, height: height)
    }

    private func drawCurrent() {
        guard let renderer = CapsulePlanShaderRenderer.shared,
              metalLayer.drawableSize.width >= 1
        else { return }
        let uniforms = CapsulePlanShaderStyle.uniforms(
            resolution: SIMD2<Float>(
                Float(metalLayer.drawableSize.width),
                Float(metalLayer.drawableSize.height)
            ),
            time: Float(CACurrentMediaTime() - startedAt),
            progress: displayedProgress,
            track: trackColor,
            backingScale: window?.backingScaleFactor ?? metalLayer.contentsScale
        )
        renderer.draw(layer: metalLayer, uniforms: uniforms)
    }
}
