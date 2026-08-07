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
    @State private var floatingNotes: [FloatingMusicNote] = []
    @State private var musicNoteTask: Task<Void, Never>?
    private var library = PetLibraryStore.shared
    private var runtime = PetRuntime.shared
    private var hookSprites = HookSpriteSettings.shared
    private var musicMonitor = MusicPlaybackMonitor.shared

    private let stackSpacing: CGFloat = 4
    private let petBubbleSpacing: CGFloat = 6
    private let basePetSize: CGFloat = 96
    /// Burst every few seconds — Pow `.rise` used TimelineView at display
    /// refresh and drove 20–30% CPU while music played.
    private static let musicNoteInterval: Duration = .seconds(4)
    private static let musicNoteFlight: Duration = .milliseconds(1600)
    private static let musicNoteStagger: Duration = .milliseconds(220)
    private static let musicNoteSymbols = [
        "music.note",
        "music.note",
        "music.quarternote.3",
    ]

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

    private var shouldEmitMusicNotes: Bool {
        AppSettings.shared.musicNotesEnabled
            && musicMonitor.isPlaying
            && panelController.isContentPresented
    }

    var body: some View {
        // Keep one layout tree (even with zero bubbles) so insert/remove
        // transitions are not torn down by switching to a pet-only branch.
        // Hide vanishes only the pet sprite (local transition) and fades bubbles —
        // never remove this root tree while resizing the NSPanel (constraint loop).
        // No root WindowDragGesture — that made music-note padding (and other
        // empty layout) steal clicks. Pet drag is AppKit performDrag on opaque
        // pixels only (PassThroughHostingView); bubbles keep their own taps.
        positionedContent
            .padding(PetContentInsets.current(musicNotesEnabled: AppSettings.shared.musicNotesEnabled).edgeInsets)
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
            // Bottom-align so upward bubble stack doesn't force empty panel below.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        case .right:
            HStack(alignment: .center, spacing: 0) {
                petImage
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

    /// `bubbleItems` are newest-first; arrow sits on the bubble nearest the pet.
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
            glassStyle: glassStyle,
            glassTint: glassTint
        )

        // Warning must open Settings via SettingsLink (openSettings() warns on current SDKs).
        if item.kind == .warning {
            SettingsLink {
                bubble
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    SettingsNavigator.shared.prepareIntegrations()
                    PetRuntime.shared.dismissBubble(id: item.id)
                }
            )
        } else {
            bubble
        }
    }

    private func dismissAction(for item: StatusBubbleItem) -> (() -> Void)? {
        // Warning dismiss is handled beside SettingsLink so we don't double-fire.
        guard item.kind != .warning, item.isDismissible else { return nil }
        return { PetRuntime.shared.dismissBubble(id: item.id) }
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

    private var petImage: some View {
        let progress = panelController.petAppearProgress
        // progress 0: above + vertically squashed; 1: settled (spring may overshoot >1).
        let clamped = max(progress, 0)
        let squash = min(max(0.72 + clamped * 0.28, 0.55), 1.2)
        let widen = min(max(1.18 - clamped * 0.18, 0.9), 1.25)
        let noteColor = PetAppearance.dominantColor(for: library.selectedRecord)

        return ZStack {
            // Keep layout size while the sprite is removed for Pow vanish.
            Color.clear
                .frame(width: petSize, height: petSize)
                .allowsHitTesting(false)

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

            ForEach(floatingNotes) { note in
                FloatingMusicNoteView(note: note, color: noteColor, petSize: petSize)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(String(localized: "Desktop pet"))
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
                await spawnMusicNoteBurst()
                try? await Task.sleep(for: Self.musicNoteInterval)
            }
        }
    }

    /// Random 1…3 notes, staggered so they ease out of phase.
    private func spawnMusicNoteBurst() async {
        let count = Int.random(in: 1 ... 3)
        for index in 0..<count {
            guard !Task.isCancelled else { return }
            if index > 0 {
                try? await Task.sleep(for: Self.musicNoteStagger)
            }
            spawnMusicNote()
        }
    }

    private func spawnMusicNote() {
        let note = FloatingMusicNote(
            systemName: Self.musicNoteSymbols.randomElement() ?? "music.note",
            xJitter: CGFloat.random(in: -14 ... 20),
            fontSize: CGFloat.random(in: 12 ... 17),
            flightSeconds: Double.random(in: 1.15 ... 1.55),
            riseDistanceFactor: CGFloat.random(in: 0.55 ... 0.85),
            sway: CGFloat.random(in: -10 ... 14)
        )
        floatingNotes.append(note)
        let noteID = note.id
        let removeAfter = Self.musicNoteFlight
        Task { @MainActor in
            try? await Task.sleep(for: removeAfter)
            floatingNotes.removeAll { $0.id == noteID }
        }
    }
}

/// One rising note driven by a single SwiftUI animation (no display-linked TimelineView).
private struct FloatingMusicNote: Identifiable {
    let id = UUID()
    let systemName: String
    let xJitter: CGFloat
    let fontSize: CGFloat
    let flightSeconds: Double
    let riseDistanceFactor: CGFloat
    let sway: CGFloat
}

private struct FloatingMusicNoteView: View {
    let note: FloatingMusicNote
    let color: Color
    let petSize: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        Image(systemName: note.systemName)
            .font(.system(size: note.fontSize, weight: .semibold))
            .foregroundStyle(color.opacity(0.85 + Double(1 - progress) * 0.15))
            .offset(
                x: petSize * 0.28 + note.xJitter + note.sway * progress,
                y: -petSize * 0.15 - progress * (petSize * note.riseDistanceFactor)
            )
            .opacity(Double(1 - progress))
            .scaleEffect(0.92 + 0.12 * (1 - progress))
            .onAppear {
                withAnimation(.easeOut(duration: note.flightSeconds)) {
                    progress = 1
                }
            }
    }
}

#Preview("stack above") {
    PetView(
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
