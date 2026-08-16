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

    var body: some View {
        Group {
            switch record.kind {
            case .builtInDefault, .staticImage:
                staticPetImage
            case .petdex:
                petdexAiboImage
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var staticPetImage: some View {
        if let image = AiboSpriteCache.shared.previewImage(for: record) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image("DefaultAibo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
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
                    lookIndex: lookFrame == nil ? nil : look?.index
                ),
                frames: frames,
                frameDuration: frameInterval(for: state),
                size: size
            )
            .frame(width: size, height: size)
        }
    }

    /// Only read the panel property while idle so agent animations don't invalidate.
    private var resolvedLookDirection: PetdexLookDirection? {
        guard followsPointer, activity == .idle else { return nil }
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
                .frame(width: size, height: size)
        }
    }

    /// Idle stays on a still frame — no animation at all (PLANS §7).
    private func shouldAnimate(_ state: PetdexSpriteState) -> Bool {
        state != .idle && activity != .idle
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
    }

    var key: Key
    var frames: [CGImage]
    var frameDuration: TimeInterval
    var size: CGFloat

    func makeNSView(context: Context) -> SpriteView {
        SpriteView()
    }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.apply(key: key, frames: frames, frameDuration: frameDuration)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SpriteView,
        context: Context
    ) -> CGSize? {
        CGSize(width: size, height: size)
    }

    final class SpriteView: NSView {
        private static let animationKey = "aibo.sprite"
        private var appliedKey: Key?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            guard let layer else { return }
            // Matches the SwiftUI rendering this replaced: scaledToFit + .none.
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

        func apply(key: Key, frames: [CGImage], frameDuration: TimeInterval) {
            guard key != appliedKey,
                  let layer,
                  let first = frames.first
            else { return }
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
