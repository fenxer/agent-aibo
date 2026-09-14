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
    @Bindable private var library = AiboLibraryStore.shared
    private var switchSignal = AiboSwitchSignal.shared
    private var runtime = AiboRuntime.shared
    private var hookSprites = HookSpriteSettings.shared
    private var musicMonitor = MusicPlaybackMonitor.shared
    @Bindable private var onboarding = OnboardingController.shared

    @Environment(\.displayScale) private var displayScale

    private let stackSpacing: CGFloat = 4
    private var aiboBubbleSpacing: CGFloat {
        CGFloat(library.selectedRecord.bubbleDistance)
    }
    private let baseAiboSize: CGFloat = 96
    private var bubbleItems: [StatusBubbleItem] {
        bubbleItemsOverride ?? runtime.bubbleItems
    }

    /// Welcome and wrap-up use `waving` (arm wave), not `waiting` (Codex approval fidget).
    /// Choose-aibo and Agent hook loop `idle`; success `jumping`; bubble-status / Cursor stack `review`.
    private var onboardingOverlaySprite: PetdexSpriteState? {
        guard onboarding.isActive || bubbleItems.contains(where: { $0.kind == .onboarding }) else {
            return nil
        }
        return onboarding.step.sprite
    }

    private var resolvedPresentation: AiboDisplayPresentation {
        if let overlay = onboardingOverlaySprite {
            return .sprite(overlay, activity: .registered)
        }
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
        if switchSignal.locksDesktopSize, switchSignal.canvasSize.width > 1 {
            return switchSignal.canvasSize
        }
        return AiboSpriteDisplay.desktopSize(
            for: library.selectedRecord,
            nominal: aiboNominalSize,
            backingScale: displayScale
        )
    }

    private var aiboSize: CGFloat {
        max(aiboLayoutSize.width, aiboLayoutSize.height)
    }

    private var launchPortalLayout: AiboLaunchPortalTimeline.Layout {
        AiboLaunchPortalTimeline.layout(aiboSize: aiboLayoutSize)
    }

    private var contentInsets: AiboContentInsets {
        AiboContentInsets.current(
            musicNotesEnabled: AppSettings.shared.musicNotesEnabled,
            launchPortal: panelController.isLaunchPortalPlaying ? launchPortalLayout : nil
        )
    }

    private var showsBubbles: Bool {
        panelController.isContentPresented && !panelController.isLaunchPortalPlaying
    }

    private func usesAgentGlass(_ item: StatusBubbleItem) -> Bool {
        item.kind == .agent
    }

    private func glassStyle(for item: StatusBubbleItem) -> BubbleGlassStyle {
        AppSettings.shared.bubbleGlassStyle(for: usesAgentGlass(item) ? item.agent : nil)
    }

    private func glassTint(for item: StatusBubbleItem) -> Color? {
        AppSettings.shared.bubbleGlassTint(for: usesAgentGlass(item) ? item.agent : nil)
    }

    private var shouldEmitMusicNotes: Bool {
        AppSettings.shared.musicNotesEnabled
            && musicMonitor.isPlaying
            && panelController.isContentPresented
            && !panelController.isLaunchPortalPlaying
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
            .padding(contentInsets.edgeInsets)
            .padding(
                .bottom,
                !panelController.isLaunchPortalPlaying && onboarding.showsActionPills
                    ? OnboardingChrome.actionPillsStackHeight
                    : 0
            )
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
            // Overlay — not a pet+stack VStack. Insert/remove (and the
            // removal `withAnimation`) would reflow that VStack and slide
            // the aibo; the panel then snaps it back. Same idea as
            // `sideAnchoredBubbleStack`: layout is the pet, stack draws away.
            aiboImage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    if showsBubbles {
                        verticallyAnchoredBubbleStack(growsUpward: true)
                    }
                }
        case .bottom:
            aiboImage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) {
                    if showsBubbles {
                        verticallyAnchoredBubbleStack(growsUpward: false)
                    }
                }
        case .left:
            HStack(alignment: .center, spacing: aiboBubbleSpacing) {
                if showsBubbles {
                    fadingSideAnchoredBubbleStack(nearPetIndex: bubbleItems.count - 1)
                }
                aiboImage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        case .right:
            HStack(alignment: .center, spacing: aiboBubbleSpacing) {
                aiboImage
                if showsBubbles {
                    fadingSideAnchoredBubbleStack(nearPetIndex: bubbleItems.count - 1)
                }
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
        VStack(alignment: stackAlignment, spacing: resolvedStackSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                bubbleRow(item: item, showsArrow: index == nearPetIndex)
            }
        }
        .animation(nil, value: items.map(\.id))
        // Hook inspect open / close: the card's height and every bubble it
        // pushes move on one curve (scoped to the card, siblings would jump).
        // Panel shrink is deferred 420ms to outlast this.
        .animation(.easeInOut(duration: 0.35), value: items.map(\.isInspecting))
    }

    @ViewBuilder
    private func bubbleRow(item: StatusBubbleItem, showsArrow: Bool) -> some View {
        switch item.kind {
        case .onboarding:
            OnboardingBubbleCluster(
                item: item,
                placement: placement,
                showsArrow: showsArrow,
                reservesArrowSlot: onboardingStackUsesIntrinsicWidth,
                glassStyle: glassStyle(for: item),
                glassTint: glassTint(for: item)
            )
        case .warning:
            // Warning must open Settings via SettingsLink (openSettings() warns on current SDKs).
            SettingsLink {
                animatedBubble(item: item, showsArrow: showsArrow)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    SettingsNavigator.shared.prepareRemoteWebhook()
                    AiboRuntime.shared.dismissBubble(id: item.id)
                }
            )
        case .agent, .webhook:
            animatedBubble(item: item, showsArrow: showsArrow)
        }
    }

    private func animatedBubble(item: StatusBubbleItem, showsArrow: Bool) -> AnimatedStatusBubble {
        AnimatedStatusBubble(
            item: item,
            placement: placement,
            showsArrow: showsArrow,
            reservesArrowSlot: onboardingStackUsesIntrinsicWidth,
            onActivate: item.isInspecting ? nil : activateAction(for: item),
            onDismiss: item.isInspecting ? nil : dismissAction(for: item),
            glassStyle: glassStyle(for: item),
            glassTint: glassTint(for: item)
        )
    }

    private func dismissAction(for item: StatusBubbleItem) -> (() -> Void)? {
        // Warning dismiss is handled beside SettingsLink so we don't double-fire.
        guard item.kind != .warning, item.isDismissible else { return nil }
        return { AiboRuntime.shared.dismissBubble(id: item.id) }
    }

    /// Top: stack above the pet, growing up. Bottom: stack below, growing down.
    /// The clear spacer holds the pet's slot so bubbles don't cover it; hit
    /// testing stays off so drag / click still land on the sprite.
    ///
    /// `fixedSize` + edge-aligned frame keeps extra panel slack on the far
    /// side of the stack. Without that, a flexible VStack packs from the top
    /// and the pet (or the near bubble) walks whenever height estimates differ.
    @ViewBuilder
    private func verticallyAnchoredBubbleStack(growsUpward: Bool) -> some View {
        let spacer = Color.clear
            .frame(width: 1, height: aiboLayoutSize.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        VStack(spacing: aiboBubbleSpacing) {
            if growsUpward {
                fadingBubbleStack(nearPetIndex: bubbleItems.count - 1)
                    .fixedSize(horizontal: false, vertical: true)
                spacer
            } else {
                spacer
                fadingBubbleStack(items: bubbleItems.reversed(), nearPetIndex: 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: growsUpward ? .bottom : .top
        )
    }

    /// Keeps the near-pet (arrow) bubble vertically centered with the aibo;
    /// newer bubbles stack upward without shifting that anchor.
    ///
    /// Uses `.overlay` (not `ZStack`) so layout height stays the near-aibo bubble
    /// only; the stack may draw upward outside that frame. A `ZStack` would
    /// expand to the full stack and collapse the panel into a constraint loop.
    @ViewBuilder
    private func sideAnchoredBubbleStack(nearPetIndex: Int) -> some View {
        // Keep the overlay's owner alive when the last card's sizing anchor
        // changes to the empty spacer, or its pending poof is destroyed too.
        ZStack {
            sideAnchor(nearPetIndex: nearPetIndex)
        }
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: sideStackOverlayAlignment) {
                bubbleStack(nearPetIndex: nearPetIndex)
                    // Overlay proposes the anchor's size; keep the stack's ideal
                    // height so multi-line bubbles aren't crushed to one line.
                    // Onboarding stacks also keep ideal width so StatusBubble's
                    // body-edge alignment guides (not the arrow tip) can apply.
                    .fixedSize(
                        horizontal: onboardingStackUsesIntrinsicWidth,
                        vertical: true
                    )
            }
    }

    /// Stable size anchor: near-aibo bubble when present, otherwise aibo height.
    /// Always the *status* face: the hook inspect face grows upward from this
    /// bottom edge instead of re-centering (see `sideNearRowHeight`).
    @ViewBuilder
    private func sideAnchor(nearPetIndex: Int) -> some View {
        if bubbleItems.indices.contains(nearPetIndex) {
            let item = Self.statusFace(of: bubbleItems[nearPetIndex])
            if item.kind == .onboarding {
                OnboardingBubbleCluster(
                    item: item,
                    placement: placement,
                    showsArrow: true,
                    animates: false,
                    glassStyle: glassStyle(for: item),
                    glassTint: glassTint(for: item)
                )
            } else {
                StatusBubble(
                    item: item,
                    placement: placement,
                    showsArrow: true,
                    glassStyle: glassStyle(for: item),
                    glassTint: glassTint(for: item)
                )
            }
        } else {
            Color.clear.frame(width: 1, height: aiboLayoutSize.height)
        }
    }

    private static func statusFace(of item: StatusBubbleItem) -> StatusBubbleItem {
        var status = item
        status.isInspecting = false
        return status
    }

    /// Top/bottom: center. Left: flush to pet (trailing). Right: flush to pet (leading).
    private var stackAlignment: HorizontalAlignment {
        switch placement {
        case .top, .bottom: .center
        case .left: .trailing
        case .right: .leading
        }
    }

    private var onboardingStackUsesIntrinsicWidth: Bool {
        bubbleItems.contains(where: { $0.kind == .onboarding }) && bubbleItems.count > 1
    }

    private var sideStackOverlayAlignment: Alignment {
        guard onboardingStackUsesIntrinsicWidth else { return .bottom }
        switch placement {
        case .right: return .bottomLeading
        case .left: return .bottomTrailing
        case .top, .bottom: return .bottom
        }
    }

    private var resolvedStackSpacing: CGFloat {
        onboardingStackUsesIntrinsicWidth
            ? OnboardingChrome.stackedBubbleSpacing
            : stackSpacing
    }

    private func activateAction(for item: StatusBubbleItem) -> (() -> Void)? {
        if onboarding.isActive, onboarding.bubbleTapAdvances,
           item.kind == .agent || item.kind == .webhook
        {
            return { onboarding.advance() }
        }
        switch item.kind {
        case .warning, .onboarding:
            // Warning opens via SettingsLink. Onboarding taps are owned by the cluster.
            return nil
        case .agent, .webhook:
            guard item.allowsSourceAppActivation, let agent = item.agent else { return nil }
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
        let playingPortal = panelController.isLaunchPortalPlaying

        return ZStack {
            // Keep layout size while the sprite is removed for Pow vanish.
            Color.clear
                .frame(width: aiboLayoutSize.width, height: aiboLayoutSize.height)
                .allowsHitTesting(false)

            if panelController.isContentPresented, !playingPortal {
                AiboSwitchingSpriteView(
                    record: library.selectedRecord,
                    activity: displayActivity,
                    spriteState: displaySpriteState,
                    size: aiboNominalSize,
                    lookDirection: onboardingOverlaySprite == nil ? displayLookDirection : nil,
                    pixelLayout: .fillWidth,
                    alwaysAnimates: onboardingOverlaySprite != nil,
                    usesPerAiboScale: true
                )
                .id("desktop-current-aibo")
                .scaleEffect(x: widen, y: squash, anchor: .bottom)
                .offset(y: (1 - clamped) * -aiboLayoutSize.height * 1.35)
                .contentShape(Rectangle())
                .contextMenu { AiboAppMenu(includesWebhookConnectivity: false) }
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
        .frame(width: aiboLayoutSize.width, height: aiboLayoutSize.height)
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
