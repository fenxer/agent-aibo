import AiboCore
import AppKit
import SwiftUI

/// Renders the selected library pet: Default / static square / Petdex atlas.
struct AiboSpriteView: View {
    var record: AiboLibraryRecord
    var activity: AiboActivityState
    var spriteState: PetdexSpriteState
    var size: CGFloat
    /// Desktop only: idle V2 pets look at the pointer via `AiboPanelController`.
    var followsPointer: Bool = false
    /// Settings Follow Mouse preview: an explicit look cell. Desktop uses `followsPointer`.
    var lookDirection: PetdexLookDirection? = nil
    var pixelLayout: AiboSpritePixelLayout = .fit
    /// Settings action preview loops Idle too; the desktop pet keeps Idle still.
    var alwaysAnimates: Bool = false

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch record.kind {
            case .builtInDefault, .staticImage:
                staticPetImage
            case .petdex:
                petdexAiboImage
            }
        }
        .frame(width: spriteSize.width, height: spriteSize.height)
        .frame(width: layoutSize.width, height: layoutSize.height)
    }

    private var usesPixelOptimization: Bool {
        AppSettings.shared.pixelOptimizationEnabled && record.kind != .builtInDefault
    }

    private var spriteSize: CGSize {
        AiboSpriteDisplay.size(
            for: record,
            nominal: size,
            backingScale: displayScale,
            layout: pixelLayout
        )
    }

    private var layoutSize: CGSize {
        switch pixelLayout {
        case .fit:
            CGSize(width: size, height: size)
        case .fillWidth:
            spriteSize
        }
    }

    private var imageInterpolation: Image.Interpolation {
        usesPixelOptimization ? .none : .high
    }

    @ViewBuilder
    private var staticPetImage: some View {
        if let image = AiboSpriteCache.shared.previewImage(for: record) {
            Image(nsImage: image)
                .resizable()
                .interpolation(imageInterpolation)
                .scaledToFit()
                .frame(width: spriteSize.width, height: spriteSize.height)
        } else {
            Image("DefaultAibo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: spriteSize.width, height: spriteSize.height)
        }
    }

    @ViewBuilder
    private var petdexAiboImage: some View {
        let animates = shouldAnimate(spriteState)
        let look = resolvedLookDirection
        let state = animates ? spriteState : .idle
        let lookFrame = look.flatMap {
            AiboSpriteCache.shared.lookLayerFrame(for: record, index: $0.index)
        }
        let frames = lookFrame.map { [$0] }
            ?? AiboSpriteCache.shared.layerFrames(for: record, state: state)
        if frames.isEmpty {
            stillFallbackImage
        } else {
            AiboSpriteLayer(
                key: AiboSpriteLayer.Key(
                    recordID: record.id,
                    state: state,
                    animates: animates,
                    lookIndex: lookFrame == nil ? nil : look?.index,
                    pixelOptimization: usesPixelOptimization
                ),
                frames: frames,
                frameDuration: frameInterval(for: state),
                size: spriteSize,
                pixelOptimization: usesPixelOptimization
            )
            .frame(width: spriteSize.width, height: spriteSize.height)
        }
    }

    /// Only read the panel property while idle so agent animations don't invalidate.
    private var resolvedLookDirection: PetdexLookDirection? {
        if let lookDirection { return lookDirection }
        guard followsPointer, activity == .idle, spriteState == .idle else { return nil }
        return AiboPanelController.shared.lookDirection
    }

    /// Shown when the atlas failed to load or yielded no frames.
    @ViewBuilder
    private var stillFallbackImage: some View {
        let image = AiboSpriteCache.shared.previewImage(for: record)
            ?? NSImage(named: "DefaultAibo")
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: spriteSize.width, height: spriteSize.height)
        }
    }

    /// Idle stays on a still frame — no animation at all (PLANS §7).
    /// Drag shares that idle slot with pointer-look; hook sprites keep `activity != .idle`.
    private func shouldAnimate(_ state: PetdexSpriteState) -> Bool {
        alwaysAnimates || state != .idle
    }

    private func frameInterval(for state: PetdexSpriteState) -> TimeInterval {
        let ms = max(state.durationMilliseconds / max(state.frameCount, 1), 80)
        return Double(ms) / 1000.0
    }
}

/// Plays a Petdex sprite loop through CoreAnimation.
///
/// A `TimelineView` re-evaluates the view graph once per display refresh
/// (60–120 Hz) just to advance a ~8 fps sprite, and handing SwiftUI a fresh
/// `NSImage` every frame forces a full `NSHostingView` layout pass plus a
/// tracking-area rebuild. A discrete keyframe animation is submitted once and
/// then played by the render server, so the main thread only does work when the
/// sprite state actually changes.
private struct AiboSpriteLayer: NSViewRepresentable {
    /// Identifies the mounted loop; the animation is rebuilt only when it changes.
    struct Key: Equatable {
        var recordID: String
        var state: PetdexSpriteState
        var animates: Bool
        var lookIndex: Int?
        var pixelOptimization: Bool
    }

    var key: Key
    var frames: [CGImage]
    var frameDuration: TimeInterval
    var size: CGSize
    var pixelOptimization: Bool

    func makeNSView(context: Context) -> SpriteView {
        SpriteView()
    }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.apply(
            key: key,
            frames: frames,
            frameDuration: frameDuration,
            pixelOptimization: pixelOptimization
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SpriteView,
        context: Context
    ) -> CGSize? {
        size
    }

    final class SpriteView: NSView {
        private static let animationKey = "aibo.sprite"
        private var appliedKey: Key?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            guard let layer else { return }
            layer.contentsGravity = .resizeAspect
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("AiboSpriteLayer.SpriteView is not loadable from a nib")
        }

        /// Let the SwiftUI frame decide the size; an intrinsic size here would
        /// feed AppKit constraints back into AiboPanel's sizing.
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            layer?.contentsScale = window?.backingScaleFactor ?? 1
        }

        func apply(
            key: Key,
            frames: [CGImage],
            frameDuration: TimeInterval,
            pixelOptimization: Bool
        ) {
            guard let layer, let first = frames.first else { return }
            layer.contentsGravity = pixelOptimization ? .resize : .resizeAspect
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            guard key != appliedKey else { return }
            appliedKey = key

            layer.removeAnimation(forKey: Self.animationKey)
            layer.contents = first
            guard key.animates, frames.count > 1, frameDuration > 0 else { return }

            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.calculationMode = .discrete
            // Discrete mode wants one more key time than values, so every frame
            // gets an equal slice and the loop closes at 1.0.
            animation.keyTimes = (0...frames.count).map {
                NSNumber(value: Double($0) / Double(frames.count))
            }
            animation.duration = frameDuration * Double(frames.count)
            animation.repeatCount = .infinity
            layer.add(animation, forKey: Self.animationKey)
        }
    }
}
