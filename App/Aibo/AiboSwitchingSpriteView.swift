import AiboCore
import AppKit
import Metal
import QuartzCore
import SwiftUI

/// Plays the mask-warp shader when the selected aibo changes.
///
/// Desktop panel resizes on `select` can rebuild this view, so morph is keyed
/// off `AiboSwitchSignal` (not `onChange(of: record.id)`). Progress is driven
/// by a short-lived screen `CADisplayLink` — SwiftUI will not interpolate into
/// `NSViewRepresentable`.
struct AiboSwitchingSpriteView: View {
    var record: AiboLibraryRecord
    var activity: AiboActivityState
    var spriteState: PetdexSpriteState
    var size: CGFloat
    var lookDirection: PetdexLookDirection? = nil
    var pixelLayout: AiboSpritePixelLayout = .fit
    var alwaysAnimates: Bool = false
    /// Desktop size follows each aibo's `scalePercent`; settings previews use a fixed slot.
    var usesPerAiboScale: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var isMorphing = false
    @State private var metalReady = false
    @State private var revealing = false
    @State private var fromImage: NSImage?
    @State private var toImage: NSImage?
    @State private var generation = 0
    @State private var handledSequence: UInt64 = 0
    @State private var morphCanvas: CGSize = .zero
    /// After a morph, ignore the current look bucket until the pointer moves.
    @State private var holdLook = false
    @State private var heldLook: PetdexLookDirection?
    private var switchSignal = AiboSwitchSignal.shared

    var body: some View {
        let sequence = switchSignal.sequence
        ZStack {
            liveSprite(
                record,
                activity: showsIncomingLive && !revealing ? activity : .idle,
                spriteState: showsIncomingLive && !revealing ? spriteState : .idle,
                look: showsIncomingLive && !revealing ? revealedLook : nil
            )
            .opacity(showsIncomingLive ? 1 : 0)

            if let outgoing = outgoingRecord, showsOutgoingLive {
                liveSprite(outgoing, activity: .idle, spriteState: .idle, look: nil)
            }

            if isMorphing, let fromImage, let toImage {
                AiboSwitchMorphView(
                    fromImage: fromImage,
                    toImage: toImage,
                    size: layoutSize,
                    generation: generation,
                    onFirstFrame: { metalReady = true },
                    onCompleted: finishMorph
                )
                .allowsHitTesting(false)
            }
        }
        .frame(width: layoutSize.width, height: layoutSize.height)
        .onChange(of: sequence, initial: true) { _, newSequence in
            consumeSwitch(newSequence)
        }
        .onChange(of: lookDirection) { _, newLook in
            guard holdLook, newLook != heldLook else { return }
            holdLook = false
        }
    }

    /// `onChange` runs after the first paint of the new record. Keep the
    /// outgoing idle sprite up until then so the incoming pet does not flash.
    private var pendingSwitch: Bool {
        switchSignal.sequence > 0
            && switchSignal.sequence != handledSequence
            && switchSignal.isFresh
            && switchSignal.toID == record.id
    }

    /// Incoming is revealed under the last Metal frame before Metal is removed,
    /// so a transparent panel never punches through to the wallpaper.
    private var showsIncomingLive: Bool {
        revealing || (!pendingSwitch && !isMorphing)
    }

    /// Hold the outgoing idle sprite until Metal has presented a frame. The
    /// settings banner is opaque; the desktop panel is not.
    private var showsOutgoingLive: Bool {
        pendingSwitch || (isMorphing && !metalReady && !revealing)
    }

    private var outgoingRecord: AiboLibraryRecord? {
        Self.record(id: switchSignal.fromID)
    }

    private var revealedLook: PetdexLookDirection? {
        if holdLook, lookDirection == heldLook { return nil }
        return lookDirection
    }

    @ViewBuilder
    private func liveSprite(
        _ spriteRecord: AiboLibraryRecord,
        activity: AiboActivityState,
        spriteState: PetdexSpriteState,
        look: PetdexLookDirection?
    ) -> some View {
        AiboSpriteView(
            record: spriteRecord,
            activity: activity,
            spriteState: spriteState,
            size: nominalSize(for: spriteRecord),
            lookDirection: look,
            pixelLayout: pixelLayout,
            alwaysAnimates: alwaysAnimates
        )
    }

    private var layoutSize: CGSize {
        if usesPerAiboScale, switchSignal.locksDesktopSize, switchSignal.canvasSize.width > 1 {
            return switchSignal.canvasSize
        }
        if isMorphing || revealing, morphCanvas.width > 1, morphCanvas.height > 1 {
            return morphCanvas
        }
        if pendingSwitch, usesPerAiboScale, switchSignal.canvasSize.width > 1 {
            return switchSignal.canvasSize
        }
        return layoutSize(for: record)
    }

    private func nominalSize(for layoutRecord: AiboLibraryRecord) -> CGFloat {
        usesPerAiboScale
            ? AiboSpriteDisplay.basePointSize * CGFloat(layoutRecord.scalePercent / 100)
            : size
    }

    private func layoutSize(for layoutRecord: AiboLibraryRecord) -> CGSize {
        AiboSpriteDisplay.size(
            for: layoutRecord,
            nominal: nominalSize(for: layoutRecord),
            backingScale: displayScale,
            layout: pixelLayout
        )
    }

    private func consumeSwitch(_ sequence: UInt64) {
        guard sequence > 0, sequence != handledSequence else { return }
        handledSequence = sequence
        guard switchSignal.isFresh, switchSignal.toID == record.id else { return }
        if !beginMorph(fromID: switchSignal.fromID), usesPerAiboScale {
            AiboSwitchSignal.shared.desktopMorphDidFinish()
        }
    }

    @discardableResult
    private func beginMorph(fromID: String) -> Bool {
        guard AiboSwitchRenderer.shared != nil,
              fromID != record.id
        else { return false }
        guard let fromRecord = Self.record(id: fromID) else { return false }
        let fromLayout = layoutSize(for: fromRecord)
        let toLayout = layoutSize(for: record)
        let canvas: CGSize
        if usesPerAiboScale, switchSignal.canvasSize.width > 1 {
            canvas = switchSignal.canvasSize
        } else {
            canvas = AiboSwitchSignal.enclosing(fromLayout, toLayout)
        }
        guard canvas.width > 1, canvas.height > 1,
              let fromImage = AiboSwitchSnapshot.image(
                  for: fromRecord,
                  drawSize: fromLayout,
                  canvas: canvas,
                  backingScale: displayScale
              ),
              let toImage = AiboSwitchSnapshot.image(
                  for: record,
                  drawSize: toLayout,
                  canvas: canvas,
                  backingScale: displayScale
              )
        else { return false }

        generation += 1
        morphCanvas = canvas
        self.fromImage = fromImage
        self.toImage = toImage
        metalReady = false
        revealing = false
        holdLook = true
        heldLook = lookDirection
        isMorphing = true
        return true
    }

    private func finishMorph(_ token: Int) {
        guard token == generation else { return }
        holdLook = true
        heldLook = lookDirection
        revealing = true
        Task { @MainActor in
            await Task.yield()
            guard token == generation else { return }
            isMorphing = false
            fromImage = nil
            toImage = nil
            metalReady = false
            revealing = false
            if usesPerAiboScale {
                await Task.yield()
                morphCanvas = .zero
                AiboSwitchSignal.shared.desktopMorphDidFinish()
            } else {
                morphCanvas = .zero
            }
        }
    }

    private static func record(id: String) -> AiboLibraryRecord? {
        if let match = AiboLibraryStore.shared.records.first(where: { $0.id == id }) {
            return match
        }
        return id == AiboLibraryDefaults.builtInID ? .builtInDefault : nil
    }
}

private struct AiboSwitchMorphView: NSViewRepresentable {
    var fromImage: NSImage
    var toImage: NSImage
    var size: CGSize
    var generation: Int
    var onFirstFrame: () -> Void
    var onCompleted: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AiboSwitchMetalView {
        AiboSwitchMetalView()
    }

    func updateNSView(_ view: AiboSwitchMetalView, context: Context) {
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.onCompleted = onCompleted
        view.apply(
            from: fromImage,
            to: toImage,
            generation: generation,
            onFirstFrame: {
                context.coordinator.onFirstFrame?()
            },
            onCompleted: { token in
                context.coordinator.onCompleted?(token)
            }
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AiboSwitchMetalView,
        context: Context
    ) -> CGSize? {
        size
    }

    final class Coordinator {
        var onFirstFrame: (() -> Void)?
        var onCompleted: ((Int) -> Void)?
    }
}

/// Owns a vsync link only while a morph is in flight; invalidated on completion
/// and when the view leaves the window.
///
/// The view layer holds a still of `from` until Metal presents, so a
/// transparent desktop panel does not flash through to the wallpaper.
private final class AiboSwitchMetalView: NSView {
    private let tickProxy = TickProxy()
    private let stillLayer = CALayer()
    private let metalLayer = CAMetalLayer()
    private var displayLink: CADisplayLink?
    private var fromTexture: MTLTexture?
    private var toTexture: MTLTexture?
    private var fromImage: NSImage?
    private var toImage: NSImage?
    private var generation = 0
    private var startedAt: CFTimeInterval = 0
    private var didNotifyFirstFrame = false
    private var onFirstFrame: (() -> Void)?
    private var onCompleted: ((Int) -> Void)?

    private final class TickProxy: NSObject {
        weak var owner: AiboSwitchMetalView?
        @objc func tick(_ link: CADisplayLink) {
            owner?.handleTick(link)
        }
    }

    init() {
        super.init(frame: .zero)
        tickProxy.owner = self
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let container = CALayer()
        container.isOpaque = false
        layer = container
        stillLayer.contentsGravity = .resize
        stillLayer.magnificationFilter = .nearest
        stillLayer.minificationFilter = .nearest
        stillLayer.isOpaque = false
        AiboSwitchRenderer.shared?.configure(metalLayer)
        container.addSublayer(stillLayer)
        container.addSublayer(metalLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AiboSwitchMetalView is not loadable from a nib")
    }

    deinit {
        displayLink?.invalidate()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var isOpaque: Bool { false }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
        drawCurrent()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            stillLayer.frame = bounds
            metalLayer.frame = bounds
            updateDrawableSize()
            if fromTexture != nil, displayLink == nil {
                startLink()
            }
            draw(progress: 0)
        } else {
            stopLink()
        }
    }

    override func layout() {
        super.layout()
        stillLayer.frame = bounds
        metalLayer.frame = bounds
        updateDrawableSize()
        drawCurrent()
    }

    func apply(
        from: NSImage,
        to: NSImage,
        generation: Int,
        onFirstFrame: @escaping () -> Void,
        onCompleted: @escaping (Int) -> Void
    ) {
        self.onFirstFrame = onFirstFrame
        self.onCompleted = onCompleted
        let sameImages = from === fromImage && to === toImage
        if sameImages, generation == self.generation {
            return
        }

        guard let renderer = AiboSwitchRenderer.shared else {
            onCompleted(generation)
            return
        }
        fromImage = from
        toImage = to
        self.generation = generation
        didNotifyFirstFrame = false
        stillLayer.isHidden = false
        stillLayer.contents = from.cgImage(forProposedRect: nil, context: nil, hints: nil)
        fromTexture = renderer.makeTexture(from: from)
        toTexture = renderer.makeTexture(from: to)
        startedAt = CACurrentMediaTime()
        stillLayer.frame = bounds
        metalLayer.frame = bounds
        updateDrawableSize()
        draw(progress: 0)
        startLink()
    }

    private func startLink() {
        stopLink()
        guard window != nil else { return }
        // Screen-level link keeps ticking on the floating, often non-key AiboPanel.
        // `NSView.displayLink` can stay silent when the view is not on the key window.
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

    private func handleTick(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startedAt
        let duration = AiboSwitchTransition.duration
        let linear = min(max(elapsed / duration, 0), 1)
        draw(progress: Float(linear))
        guard linear >= 1 else { return }
        stopLink()
        let token = generation
        let finish = onCompleted
        DispatchQueue.main.async {
            finish?(token)
        }
    }

    private func drawCurrent() {
        guard displayLink != nil else { return }
        let elapsed = CACurrentMediaTime() - startedAt
        let duration = max(AiboSwitchTransition.duration, 0.001)
        draw(progress: Float(min(max(elapsed / duration, 0), 1)))
    }

    private func draw(progress: Float) {
        guard let renderer = AiboSwitchRenderer.shared,
              let fromTexture,
              let toTexture,
              bounds.width > 1,
              bounds.height > 1
        else { return }
        renderer.draw(layer: metalLayer, from: fromTexture, to: toTexture, progress: progress)
        if !didNotifyFirstFrame {
            didNotifyFirstFrame = true
            stillLayer.isHidden = true
            let notify = onFirstFrame
            DispatchQueue.main.async {
                notify?()
            }
        }
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        stillLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(metalLayer.bounds.width * scale, 1),
            height: max(metalLayer.bounds.height * scale, 1)
        )
    }
}

private enum AiboSwitchSnapshot {
    @MainActor
    static func image(
        for record: AiboLibraryRecord,
        drawSize: CGSize,
        canvas: CGSize,
        backingScale: CGFloat
    ) -> NSImage? {
        let source = AiboSpriteCache.shared.previewImage(for: record)
            ?? NSImage(named: "DefaultAibo")
        guard let source,
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              drawSize.width > 0,
              drawSize.height > 0,
              canvas.width > 0,
              canvas.height > 0,
              backingScale > 0
        else { return nil }

        let pixelWidth = max(Int((canvas.width * backingScale).rounded()), 1)
        let pixelHeight = max(Int((canvas.height * backingScale).rounded()), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = record.pixelOptimizationEnabled && record.kind != .builtInDefault
            ? .none
            : .high

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let slotWidth = drawSize.width * backingScale
        let slotHeight = drawSize.height * backingScale
        let fit = min(slotWidth / sourceWidth, slotHeight / sourceHeight)
        let drawWidth = sourceWidth * fit
        let drawHeight = sourceHeight * fit
        let originX = (CGFloat(pixelWidth) - drawWidth) / 2
        let originY = (CGFloat(pixelHeight) - drawHeight) / 2
        context.draw(
            cgImage,
            in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight)
        )
        guard let rendered = context.makeImage() else { return nil }
        return NSImage(cgImage: rendered, size: canvas)
    }
}
