import AiboCore
import Pow
import SwiftUI

struct AiboView: View {
    /// Preview / test override; `nil` reads `AiboRuntime.shared`.
    var bubbleItemsOverride: [StatusBubbleItem]? = nil
    /// Preview / test override; `nil` reads `AppSettings.shared`.
    var placementOverride: BubblePlacement? = nil
    /// Preview / test override; `nil` derives from the selected aibo's `scalePercent`.
    var aiboSizeOverride: CGFloat? = nil

    @State private var panelController = AiboPanelController.shared
    @State private var floatingNotes: [FloatingMusicNote] = []
    @State private var musicNoteTask: Task<Void, Never>?
    private var library = AiboLibraryStore.shared
    private var runtime = AiboRuntime.shared
    private var hookSprites = HookSpriteSettings.shared
    private var musicMonitor = MusicPlaybackMonitor.shared

    @Environment(\.displayScale) private var displayScale

    private let stackSpacing: CGFloat = 4
    private var aiboBubbleSpacing: CGFloat {
        CGFloat(library.selectedRecord.bubbleDistance)
    }
    private let baseAiboSize: CGFloat = 96
    private var bubbleItems: [StatusBubbleItem] {
        bubbleItemsOverride ?? runtime.bubbleItems
    }

    private var resolvedPresentation: AiboDisplayPresentation {
        _ = hookSprites.file
        let look = AppSettings.shared.disableMouseTracking
            ? nil
            : panelController.lookDirection
        return AiboActionMapping.presentation(
            sessions: runtime.world.sessions,
            spriteFor: { key, snapshot in runtime.sprite(for: key, snapshot: snapshot) },
            dragSprite: panelController.dragActionSprite,
            lookDirection: look
        )
    }

    private var displaySpriteState: PetdexSpriteState {
        switch resolvedPresentation {
        case .sprite(let state, _): state
        case .look: .idle
        }
    }

    private var displayActivity: AiboActivityState {
        switch resolvedPresentation {
        case .sprite(_, let activity): activity
        case .look: .idle
        }
    }

    private var displayLookDirection: PetdexLookDirection? {
        switch resolvedPresentation {
        case .sprite: nil
        case .look(let direction): direction
        }
    }

    private var placement: BubblePlacement {
        placementOverride ?? library.selectedRecord.bubblePlacement
    }

    private var aiboNominalSize: CGFloat {
        aiboSizeOverride ?? baseAiboSize * CGFloat(library.selectedRecord.scalePercent / 100)
    }

    private var aiboLayoutSize: CGSize {
        AiboSpriteDisplay.desktopSize(
            for: library.selectedRecord,
            nominal: aiboNominalSize,
            backingScale: displayScale
        )
    }

    private var aiboSize: CGFloat {
        max(aiboLayoutSize.width, aiboLayoutSize.height)
    }

    private func glassStyle(for item: StatusBubbleItem) -> BubbleGlassStyle {
        AppSettings.shared.bubbleGlassStyle(for: item.kind == .agent ? item.agent : nil)
    }

    private func glassTint(for item: StatusBubbleItem) -> Color? {
        AppSettings.shared.bubbleGlassTint(for: item.kind == .agent ? item.agent : nil)
    }

    private var shouldEmitMusicNotes: Bool {
        AppSettings.shared.musicNotesEnabled
            && musicMonitor.isPlaying
            && panelController.isContentPresented
    }

    private var musicNoteColor: Color {
        AppSettings.shared.resolvedMusicNotesColor(for: library.selectedRecord)
    }

    var body: some View {
        // Keep one layout tree (even with zero bubbles) so insert/remove
        // transitions are not torn down by switching to a pet-only branch.
        // Hide vanishes only the aibo sprite (local transition) and fades bubbles —
        // never remove this root tree while resizing the NSPanel (constraint loop).
        // No root WindowDragGesture — that made music-note padding (and other
        // empty layout) steal clicks. Pet drag is AppKit mouse tracking on opaque
        // pixels only (PassThroughHostingView); bubbles keep their own taps.
        positionedContent
            .padding(AiboContentInsets.current(musicNotesEnabled: AppSettings.shared.musicNotesEnabled).edgeInsets)
            .allowsWindowActivationEvents()
            .onChange(of: shouldEmitMusicNotes, initial: true) { _, active in
                syncMusicNotePulse(active: active)
            }
            .onDisappear {
                musicNoteTask?.cancel()
                musicNoteTask = nil
                floatingNotes.removeAll()
            }
    }

    @ViewBuilder
    private var positionedContent: some View {
        switch placement {
        case .top:
            VStack(spacing: aiboBubbleSpacing) {
                fadingBubbleStack(nearPetIndex: bubbleItems.count - 1)
                aiboImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .bottom:
            VStack(spacing: aiboBubbleSpacing) {
                aiboImage
                // Oldest nearest pet (arrow); newer grow downward.
                fadingBubbleStack(items: bubbleItems.reversed(), nearPetIndex: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .left:
            HStack(alignment: .center, spacing: aiboBubbleSpacing) {
                // Layout height = near-aibo bubble only; older bubbles grow upward.
                fadingSideAnchoredBubbleStack(nearPetIndex: bubbleItems.count - 1)
                aiboImage
            }
            // Bottom-align so upward bubble stack doesn't force empty panel below.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        case .right:
            HStack(alignment: .center, spacing: aiboBubbleSpacing) {
                aiboImage
                fadingSideAnchoredBubbleStack(nearPetIndex: bubbleItems.count - 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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

    /// `bubbleItems` are newest-first; arrow sits on the bubble nearest the aibo.
    @ViewBuilder
    private func bubbleStack(nearPetIndex: Int) -> some View {
        bubbleStack(items: bubbleItems, nearPetIndex: nearPetIndex)
    }

    @ViewBuilder
    private func bubbleStack(items: [StatusBubbleItem], nearPetIndex: Int) -> some View {
        VStack(alignment: stackAlignment, spacing: stackSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                bubbleRow(
                    item: item,
                    showsArrow: index == nearPetIndex
                )
            }
        }
        .animation(nil, value: items.map(\.id))
    }

    @ViewBuilder
    private func bubbleRow(item: StatusBubbleItem, showsArrow: Bool) -> some View {
        let bubble = AnimatedStatusBubble(
            item: item,
            placement: placement,
            showsArrow: showsArrow,
            onActivate: activateAction(for: item),
            onDismiss: dismissAction(for: item),
            glassStyle: glassStyle(for: item),
            glassTint: glassTint(for: item)
        )

        // Warning must open Settings via SettingsLink (openSettings() warns on current SDKs).
        if item.kind == .warning {
            SettingsLink {
                bubble
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    SettingsNavigator.shared.prepareRemoteWebhook()
                    AiboRuntime.shared.dismissBubble(id: item.id)
                }
            )
        } else {
            bubble
        }
    }

    private func dismissAction(for item: StatusBubbleItem) -> (() -> Void)? {
        // Warning dismiss is handled beside SettingsLink so we don't double-fire.
        guard item.kind != .warning, item.isDismissible else { return nil }
        return { AiboRuntime.shared.dismissBubble(id: item.id) }
    }

    /// Keeps the near-pet (arrow) bubble vertically centered with the aibo;
    /// newer bubbles stack upward without shifting that anchor.
    ///
    /// Uses `.overlay` (not `ZStack`) so layout height stays the near-aibo bubble
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

    /// Stable size anchor: near-aibo bubble when present, otherwise aibo height.
    @ViewBuilder
    private func sideAnchor(nearPetIndex: Int) -> some View {
        if bubbleItems.indices.contains(nearPetIndex) {
            StatusBubble(
                item: bubbleItems[nearPetIndex],
                placement: placement,
                showsArrow: true,
                glassStyle: glassStyle(for: bubbleItems[nearPetIndex]),
                glassTint: glassTint(for: bubbleItems[nearPetIndex])
            )
        } else {
            Color.clear.frame(width: 1, height: aiboLayoutSize.height)
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

    private func activateAction(for item: StatusBubbleItem) -> (() -> Void)? {
        switch item.kind {
        case .warning:
            // Opened via SettingsLink wrapper — no programmatic openSettings.
            return nil
        case .agent, .webhook:
            guard let agent = item.agent else { return nil }
            return { SourceAppActivator.activate(agent) }
        }
    }

    private var aiboImage: some View {
        let progress = panelController.aiboAppearProgress
        // progress 0: above + vertically squashed; 1: settled (spring may overshoot >1).
        let clamped = max(progress, 0)
        let squash = min(max(0.72 + clamped * 0.28, 0.55), 1.2)
        let widen = min(max(1.18 - clamped * 0.18, 0.9), 1.25)
        let noteColor = musicNoteColor

        return ZStack {
            // Keep layout size while the sprite is removed for Pow vanish.
            Color.clear
                .frame(width: aiboLayoutSize.width, height: aiboLayoutSize.height)
                .allowsHitTesting(false)

            if panelController.isContentPresented {
                AiboSpriteView(
                    record: library.selectedRecord,
                    activity: displayActivity,
                    spriteState: displaySpriteState,
                    size: aiboNominalSize,
                    lookDirection: displayLookDirection,
                    pixelLayout: .fillWidth
                )
                .id("\(library.selectedID)-\(library.selectedRecord.pixelOptimizationEnabled)")
                .scaleEffect(x: widen, y: squash, anchor: .bottom)
                .offset(y: (1 - clamped) * -aiboLayoutSize.height * 1.35)
                .contentShape(Rectangle())
                .contextMenu { AiboAppMenu() }
                // Insertion must stay `.identity` — Pow `.boing` is a GeometryEffect
                // that makes NSHostingView zero out AiboPanel's width.
                .transition(
                    .asymmetric(
                        insertion: .identity,
                        removal: .movingParts.vanish(
                            AiboAppearance.dominantColor(for: library.selectedRecord),
                            increasedBrightness: false
                        )
                    )
                )
            }

            ForEach(floatingNotes) { note in
                FloatingMusicNoteView(note: note, color: noteColor, aiboSize: aiboSize)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(String(localized: "Desktop aibo"))
    }

    private func syncMusicNotePulse(active: Bool) {
        musicNoteTask?.cancel()
        musicNoteTask = nil
        guard active else {
            floatingNotes.removeAll()
            return
        }
        musicNoteTask = Task { @MainActor in
            while !Task.isCancelled {
                await MusicNoteMotion.spawnBurst(into: $floatingNotes)
                try? await Task.sleep(for: MusicNoteMotion.pulseInterval)
            }
        }
    }
}

#Preview("stack above") {
    AiboView(
        bubbleItemsOverride: [
            StatusBubbleItem(
                id: "1",
                text: "got stuck?",
                lastEventAt: .now,
                animatesEllipsis: false,
                isAwaitingApproval: true,
                agentName: "Codex",
                iconAssetName: "codex",
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
    AiboView(
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
