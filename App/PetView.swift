import AiboCore
import Pow
import SwiftUI

struct PetView: View {
    /// Preview / test override; `nil` reads `PetRuntime.shared`.
    var bubbleItemsOverride: [StatusBubbleItem]? = nil
    /// Preview / test override; `nil` reads `AppSettings.shared`.
    var placementOverride: BubblePlacement? = nil
    /// Preview / test override; `nil` derives from `AppSettings.shared.petScalePercent`.
    var petSizeOverride: CGFloat? = nil

    @State private var panelController = PetPanelController.shared
    private var library = PetLibraryStore.shared
    private var runtime = PetRuntime.shared
    private var hookSprites = HookSpriteSettings.shared

    private let stackSpacing: CGFloat = 4
    private let petBubbleSpacing: CGFloat = 6
    private let basePetSize: CGFloat = 96

    private var bubbleItems: [StatusBubbleItem] {
        bubbleItemsOverride ?? runtime.bubbleItems
    }

    private var resolvedSpriteState: PetdexSpriteState {
        _ = hookSprites.file
        return runtime.primarySpriteState
    }

    private var placement: BubblePlacement {
        placementOverride ?? AppSettings.shared.bubblePlacement
    }

    private var petSize: CGFloat {
        petSizeOverride ?? basePetSize * CGFloat(AppSettings.shared.petScalePercent / 100)
    }

    private var glassStyle: BubbleGlassStyle {
        AppSettings.shared.bubbleGlassStyle
    }

    private var glassTint: Color? {
        AppSettings.shared.bubbleGlassTint
    }

    var body: some View {
        // Keep one layout tree (even with zero bubbles) so insert/remove
        // transitions are not torn down by switching to a pet-only branch.
        // Hide vanishes only the pet sprite (local transition) and fades bubbles —
        // never remove this root tree while resizing the NSPanel (constraint loop).
        positionedContent
            .padding(8)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
    }

    @ViewBuilder
    private var positionedContent: some View {
        switch placement {
        case .top:
            VStack(spacing: petBubbleSpacing) {
                fadingBubbleStack(nearPetIndex: bubbleItems.count - 1)
                petImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .bottom:
            VStack(spacing: petBubbleSpacing) {
                petImage
                // Oldest nearest pet (arrow); newer grow downward.
                fadingBubbleStack(items: bubbleItems.reversed(), nearPetIndex: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .left:
            HStack(alignment: .center, spacing: 0) {
                // Layout height = near-pet bubble only; older bubbles grow upward.
                fadingSideAnchoredBubbleStack(nearPetIndex: bubbleItems.count - 1)
                petImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case .right:
            HStack(alignment: .center, spacing: 0) {
                petImage
                fadingSideAnchoredBubbleStack(nearPetIndex: bubbleItems.count - 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func fadingBubbleStack(nearPetIndex: Int) -> some View {
        fadingBubbleStack(items: bubbleItems, nearPetIndex: nearPetIndex)
    }

    @ViewBuilder
    private func fadingBubbleStack(items: [StatusBubbleItem], nearPetIndex: Int) -> some View {
        bubbleStack(items: items, nearPetIndex: nearPetIndex)
            .opacity(panelController.isContentPresented ? 1 : 0)
    }

    @ViewBuilder
    private func fadingSideAnchoredBubbleStack(nearPetIndex: Int) -> some View {
        sideAnchoredBubbleStack(nearPetIndex: nearPetIndex)
            .opacity(panelController.isContentPresented ? 1 : 0)
    }

    /// `bubbleItems` are newest-first; arrow sits on the bubble nearest the pet.
    @ViewBuilder
    private func bubbleStack(nearPetIndex: Int) -> some View {
        bubbleStack(items: bubbleItems, nearPetIndex: nearPetIndex)
    }

    @ViewBuilder
    private func bubbleStack(items: [StatusBubbleItem], nearPetIndex: Int) -> some View {
        VStack(alignment: stackAlignment, spacing: stackSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                AnimatedStatusBubble(
                    item: item,
                    placement: placement,
                    showsArrow: index == nearPetIndex,
                    onDismiss: item.isDismissible
                        ? { PetRuntime.shared.dismissBubble(id: item.id) }
                        : nil,
                    glassStyle: glassStyle,
                    glassTint: glassTint
                )
            }
        }
        .animation(nil, value: items.map(\.id))
    }

    /// Keeps the near-pet (arrow) bubble vertically centered with the pet;
    /// newer bubbles stack upward without shifting that anchor.
    ///
    /// Uses `.overlay` (not `ZStack`) so layout height stays the near-pet bubble
    /// only; the stack may draw upward outside that frame. A `ZStack` would
    /// expand to the full stack and collapse the panel into a constraint loop.
    @ViewBuilder
    private func sideAnchoredBubbleStack(nearPetIndex: Int) -> some View {
        sideAnchor(nearPetIndex: nearPetIndex)
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .bottom) {
                bubbleStack(nearPetIndex: nearPetIndex)
                    // Overlay proposes the anchor's size; keep the stack's ideal height
                    // so multi-line bubbles aren't crushed to one line.
                    .fixedSize(horizontal: false, vertical: true)
            }
    }

    /// Stable size anchor: near-pet bubble when present, otherwise pet height.
    @ViewBuilder
    private func sideAnchor(nearPetIndex: Int) -> some View {
        if bubbleItems.indices.contains(nearPetIndex) {
            StatusBubble(
                item: bubbleItems[nearPetIndex],
                placement: placement,
                showsArrow: true,
                glassStyle: glassStyle,
                glassTint: glassTint
            )
        } else {
            Color.clear.frame(width: 1, height: petSize)
        }
    }

    /// Top/bottom: center. Left: flush to pet (trailing). Right: flush to pet (leading).
    private var stackAlignment: HorizontalAlignment {
        switch placement {
        case .top, .bottom: .center
        case .left: .trailing
        case .right: .leading
        }
    }

    private var petImage: some View {
        let progress = panelController.petAppearProgress
        // progress 0: above + vertically squashed; 1: settled (spring may overshoot >1).
        let clamped = max(progress, 0)
        let squash = min(max(0.72 + clamped * 0.28, 0.55), 1.2)
        let widen = min(max(1.18 - clamped * 0.18, 0.9), 1.25)

        return ZStack {
            // Keep layout size while the sprite is removed for Pow vanish.
            Color.clear
                .frame(width: petSize, height: petSize)

            if panelController.isContentPresented {
                PetSpriteView(
                    record: library.selectedRecord,
                    activity: runtime.world.primarySession?.snapshot.activity ?? .idle,
                    spriteState: resolvedSpriteState,
                    size: petSize
                )
                .id(library.selectedID)
                .scaleEffect(x: widen, y: squash, anchor: .bottom)
                .offset(y: (1 - clamped) * -petSize * 1.35)
                .contentShape(Rectangle())
                .contextMenu { AiboAppMenu() }
                // Insertion must stay `.identity` — Pow `.boing` is a GeometryEffect
                // that makes NSHostingView zero out PetPanel's width.
                .transition(
                    .asymmetric(
                        insertion: .identity,
                        removal: .movingParts.vanish(
                            PetAppearance.dominantColor(for: library.selectedRecord),
                            increasedBrightness: false
                        )
                    )
                )
            }
        }
        .accessibilityLabel(String(localized: "Desktop pet"))
    }
}

#Preview("stack above") {
    PetView(
        bubbleItemsOverride: [
            StatusBubbleItem(
                id: "1",
                text: "is waiting for you",
                lastEventAt: .now,
                agentName: "Codex",
                projectName: "aibo"
            ),
            StatusBubbleItem(
                id: "2",
                text: "is thinking",
                lastEventAt: .now.addingTimeInterval(-1),
                agentName: "Cursor",
                iconAssetName: "cursor",
                projectName: "design-fragments",
                modelName: "Grok 4.5 High Fast"
            ),
        ],
        placementOverride: .top
    )
}

#Preview("left stack") {
    PetView(
        bubbleItemsOverride: [
            StatusBubbleItem(
                id: "1",
                text: "is thinking",
                lastEventAt: .now,
                agentName: "Cursor",
                iconAssetName: "cursor",
                projectName: "aibo",
                modelName: "Composer"
            ),
            StatusBubbleItem(
                id: "2",
                text: "session started",
                lastEventAt: .now.addingTimeInterval(-1),
                agentName: "Cursor",
                iconAssetName: "cursor"
            ),
            StatusBubbleItem(
                id: "3",
                text: "session started",
                lastEventAt: .now.addingTimeInterval(-2),
                agentName: "Cursor",
                iconAssetName: "cursor"
            ),
        ],
        placementOverride: .left
    )
}
