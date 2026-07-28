import AiboCore
import AppKit
import SwiftUI

/// Renders the selected library pet: Default / static square / Petdex atlas.
struct PetSpriteView: View {
    var record: PetLibraryRecord
    var activity: PetActivityState
    var size: CGFloat

    var body: some View {
        Group {
            switch record.kind {
            case .builtInDefault, .staticImage:
                staticPetImage
            case .petdex:
                petdexPetImage
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var staticPetImage: some View {
        if let image = PetSpriteCache.shared.previewImage(for: record) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image("DefaultPet")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var petdexPetImage: some View {
        let spriteState = PetdexSpriteStateMapper.state(for: activity)
        if shouldAnimate(spriteState) {
            TimelineView(.animation(minimumInterval: frameInterval(for: spriteState))) { timeline in
                let index = frameIndex(at: timeline.date, state: spriteState)
                frameImage(state: spriteState, index: index)
            }
        } else {
            frameImage(state: .idle, index: 0)
        }
    }

    private func frameImage(state: PetdexSpriteState, index: Int) -> some View {
        let image = PetSpriteCache.shared.frame(for: record, state: state, frameIndex: index)
            ?? PetSpriteCache.shared.previewImage(for: record)
            ?? NSImage(named: "DefaultPet")
        return Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
    }

    /// Idle stays on a still frame — no TimelineView (PLANS §7).
    private func shouldAnimate(_ state: PetdexSpriteState) -> Bool {
        state != .idle && activity != .idle
    }

    private func frameInterval(for state: PetdexSpriteState) -> TimeInterval {
        let ms = max(state.durationMilliseconds / max(state.frameCount, 1), 80)
        return Double(ms) / 1000.0
    }

    private func frameIndex(at date: Date, state: PetdexSpriteState) -> Int {
        let interval = frameInterval(for: state)
        guard interval > 0 else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / interval)
    }
}
