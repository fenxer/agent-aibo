import AiboCore
import AppKit
import Metal
import QuartzCore

/// AppKit Metal overlay for the first-launch portal. The panel controller
/// centers this view on the real aibo slot; the shader treats the view center
/// as the landing. Progress is a short-lived screen `CADisplayLink`.
final class AiboLaunchPortalMetalView: NSView {
    private let tickProxy = TickProxy()
    private let metalLayer = CAMetalLayer()
    private var displayLink: CADisplayLink?
    private var texture: MTLTexture?
    private var image: NSImage?
    private var aiboSize: CGSize = .zero
    private var usesNearest = false
    private var generation = 0
    private var startedAt: CFTimeInterval = 0
    private var didFinish = false
    private var onCompleted: (() -> Void)?

    private final class TickProxy: NSObject {
        weak var owner: AiboLaunchPortalMetalView?
        @objc func tick(_ link: CADisplayLink) {
            owner?.handleTick()
        }
    }

    init() {
        super.init(frame: .zero)
        tickProxy.owner = self
        wantsLayer = true
        clipsToBounds = false
        layerContentsRedrawPolicy = .never
        AiboLaunchPortalRenderer.shared?.configure(metalLayer)
        layer = metalLayer
        metalLayer.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AiboLaunchPortalMetalView is not loadable from a nib")
    }

    deinit {
        displayLink?.invalidate()
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
        drawCurrent()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        if window != nil {
            if texture != nil, displayLink == nil, !didFinish {
                startLink()
            }
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

    func apply(
        image: NSImage,
        aiboSize: CGSize,
        usesNearest: Bool,
        generation: Int,
        onCompleted: @escaping () -> Void
    ) {
        self.onCompleted = onCompleted
        self.aiboSize = aiboSize
        self.usesNearest = usesNearest
        let sameImage = image === self.image
        if sameImage, generation == self.generation {
            drawCurrent()
            return
        }

        guard let renderer = AiboLaunchPortalRenderer.shared else {
            onCompleted()
            return
        }
        self.image = image
        self.generation = generation
        didFinish = false
        texture = renderer.makeTexture(from: image)
        startedAt = CACurrentMediaTime()
        updateDrawableSize()
        drawCurrent()
        startLink()
    }

    private func startLink() {
        stopLink()
        guard window != nil else { return }
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
        drawCurrent()
        let elapsed = CACurrentMediaTime() - startedAt
        guard elapsed >= AiboLaunchPortalTimeline.duration, !didFinish else { return }
        didFinish = true
        stopLink()
        let finish = onCompleted
        DispatchQueue.main.async {
            finish?()
        }
    }

    private func drawCurrent() {
        guard let renderer = AiboLaunchPortalRenderer.shared,
              let texture,
              bounds.width > 1,
              bounds.height > 1,
              !didFinish
        else { return }
        let elapsed = max(0, CACurrentMediaTime() - startedAt)
        let frame = AiboLaunchPortalTimeline.frame(at: elapsed)
        renderer.draw(
            layer: metalLayer,
            texture: texture,
            frame: frame,
            aiboSize: aiboSize,
            nearestSprite: usesNearest,
            elapsed: Float(elapsed)
        )
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
    }
}
