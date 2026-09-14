import AiboCore
import AppKit
import SwiftUI

@MainActor
@Observable
final class AiboPanelController {
    static let shared = AiboPanelController()

    private(set) var isVisible = false
    /// When false, the aibo sprite vanishes (Pow); panel `orderOut` follows after the effect.
    private(set) var isContentPresented = true
    /// 0 = above / squashed, 1 = settled. Explicit show motion (not Pow boing).
    private(set) var aiboAppearProgress: CGFloat = 1
    /// Cold-launch / onboarding opening portal jump. Display-link Metal, not SwiftUI.
    private(set) var isLaunchPortalPlaying = false
    private(set) var launchPortalGeneration = 0
    private var hasPlayedLaunchPortal = false
    private var portalPlayback: AiboLaunchPortalTimeline.Playback = .forward
    private var isQuitPortalPlaying = false
    private var quitPortalCompletion: (() -> Void)?
    /// V2 idle look cell toward the pointer; `nil` in the deadzone or on V1.
    private(set) var lookDirection: PetdexLookDirection?
    /// True while the user is dragging the aibo from an opaque pixel.
    private(set) var isPetDragging = false
    /// Mapped drag animation once horizontal direction is known; `nil` before that.
    private(set) var dragActionSprite: PetdexSpriteState?
    private var pendingDragDeltaX: CGFloat = 0
    /// Horizontal drag must exceed this before the run animation (or a reverse) kicks in.
    private static let dragDirectionThreshold: CGFloat = 4
    private var isPetDodging = false
    private var shakeDetector = MouseShakeDetector()
    private let dodgeAnimator = AiboDodgeAnimator()

    private var isRepositioningAibo: Bool { isPetDragging || isPetDodging }

    private var shakeConfig: MouseShakeConfig {
        #if DEBUG
        MouseShakeDebugSettings.shared.config
        #else
        MouseShakeConfig()
        #endif
    }

    private var panel: AiboPanel?
    private var rootView: AiboPanelRootView?
    private var hostingView: PassThroughHostingView<AiboView>?
    private var launchPortalView: AiboLaunchPortalMetalView?
    #if DEBUG
    private var hitRegionDebugOverlay: HitRegionDebugOverlay?
    /// Development → Hit Regions: paint panel / padding / aiboHitRect / opaque drag mask.
    var showHitRegionDebug = false {
        didSet { refreshHitRegionDebugOverlay() }
    }
    #endif
    private var screenObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private let fullscreenMonitor = FullscreenSpaceMonitor()
    /// True while hide-when-fullscreen is suppressing the panel (not user Hide Aibo).
    private var isSuppressedForFullscreen = false
    private var hasPlacedInitially = false
    private var hideTask: Task<Void, Never>?
    /// Last layout we sized/positioned for — used to keep the aibo fixed on screen.
    private var laidOutBubbleCount = 0
    private var laidOutPlacement: BubblePlacement = .top
    private var laidOutAiboSize: CGSize = CGSize(width: 96, height: 96)
    /// Committed slot in bottom-left panel coordinates. Never reconstruct an old
    /// slot from current settings: portal padding may already have changed.
    private var laidOutAiboFrame: CGRect = .zero
    private var laidOutLaunchPortalPlaying = false
    private var laidOutAiboCenter: CGPoint {
        CGPoint(x: laidOutAiboFrame.midX, y: laidOutAiboFrame.midY)
    }
    private var laidOutOnboardingLayoutID = ""
    private var laidOutAiboBubbleSpacing: CGFloat = 6

    private let baseAiboSize: CGFloat = 96
    private let screenPadding: CGFloat = 24
    private let bubbleMaxWidth: CGFloat = 320
    private let bubbleEstimatedHeight: CGFloat = 88
    private var bubbleStackSpacing: CGFloat {
        let items = AiboRuntime.shared.bubbleItems
        if items.contains(where: { $0.kind == .onboarding }), items.count > 1 {
            return OnboardingChrome.stackedBubbleSpacing
        }
        return 4
    }
    /// Matches `AiboView.aiboBubbleSpacing` (aibo ↔ bubble stack gap).
    private var aiboBubbleSpacing: CGFloat {
        CGFloat(AiboLibraryStore.shared.selectedRecord.bubbleDistance)
    }
    /// Extra panel slack beyond the configured gap so estimated bubble height can undershoot.
    private let panelBubbleSlack: CGFloat = 14
    private let bubbleContentPadding: CGFloat = 12
    private let bubbleHeaderLineHeight: CGFloat = 15
    private let bubbleSectionSpacing: CGFloat = 12
    private let bubbleStatusLineHeight: CGFloat = 24
    private let bubbleCapsuleWidthEstimate: CGFloat = 88
    /// Extra width when the Codex checklist (`1/3`) is inside the capsule.
    private let bubbleCapsulePlanProgressExtra: CGFloat = 64
    private let bubbleArrowSlack: CGFloat = 6
    private let bubbleRowSpacing: CGFloat = 8

    private var onboardingActionPillsHeight: CGFloat {
        if isLaunchPortalPlaying { return 0 }
        return OnboardingController.shared.showsActionPills
            ? OnboardingChrome.actionPillsStackHeight
            : 0
    }

    private var contentInsets: AiboContentInsets {
        AiboContentInsets.current(
            musicNotesEnabled: AppSettings.shared.musicNotesEnabled,
            launchPortal: isLaunchPortalPlaying
                ? AiboLaunchPortalTimeline.layout(aiboSize: currentAiboSize)
                : nil
        )
    }

    private func effectiveBubbleCount(_ items: [StatusBubbleItem]) -> Int {
        isLaunchPortalPlaying ? 0 : items.count
    }

    private init() {
        fullscreenMonitor.screenProvider = { [weak self] in
            self?.panel?.screen ?? NSScreen.main
        }
        fullscreenMonitor.onChange = { [weak self] isFullscreen in
            self?.handleFullscreenMonitorChange(isFullscreen)
        }
        fullscreenMonitor.onReaffirmVisible = { [weak self] in
            self?.reaffirmPetVisibilityIfNeeded()
        }
    }

    func show() {
        if isQuitPortalPlaying { return }
        hideTask?.cancel()
        hideTask = nil

        let panel = panel ?? makePanel()
        self.panel = panel
        applyFullscreenCollectionBehavior(to: panel)
        // Arm the portal before the first layout so onboarding bubbles never
        // occupy the slot, then get hidden a frame later.
        let isFirstShow = !hasPlacedInitially
        if isFirstShow {
            armLaunchPortalIfNeeded()
        }
        // Menu / launch path — safe to size synchronously (not inside a layout pass).
        applyGeometryNow()
        if isFirstShow {
            placeInitially()
            hasPlacedInitially = true
            attachLaunchPortalViewIfPlaying()
        } else {
            clampToVisibleScreen()
        }

        // First launch: already presented. After hide: re-insert with identity, then
        // spring aiboAppearProgress (Pow `.boing` GeometryEffect collapses this panel).
        // Portal owns the first-show motion — do not also boing, or the live sprite
        // would pop from the landing pose into a falling squash.
        let shouldBoing = !isContentPresented && !isLaunchPortalPlaying
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if shouldBoing {
                aiboAppearProgress = 0
                isContentPresented = true
            } else {
                aiboAppearProgress = 1
                isContentPresented = true
            }
        }

        freezePanelSize()
        isVisible = true
        startObservingScreenChangesIfNeeded()
        startClickThroughMonitoringIfNeeded()
        refreshLookDirection()
        syncFullscreenPolicy()

        // Keep the panel ordered in. When hide-when-fullscreen is on we use
        // moveToActiveSpace (not canJoinAllSpaces) so the aibo leaves with its
        // desktop during the fullscreen zoom instead of floating over it.
        panel.orderFrontRegardless()
        applyFullscreenVisibility()

        if shouldBoing {
            hideTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(AiboAppearance.boingAnimation) {
                    aiboAppearProgress = 1
                }
                hideTask = nil
            }
        }
        PlaytimeStore.shared.noteVisibilityChanged()
    }

    func hide() {
        guard isVisible, !isQuitPortalPlaying else { return }
        cancelDodge(persist: true)
        isVisible = false
        PlaytimeStore.shared.noteVisibilityChanged()
        hideTask?.cancel()

        hideTask = Task { @MainActor in
            // Let the menu dismiss finish — mutating the panel during that layout pass
            // triggers NSHostingView constraint recursion.
            await Task.yield()
            guard !Task.isCancelled else { return }

            freezePanelSize()
            // Do not setFrame / resize here. Vanish must run against a stable panel size.
            withAnimation(AiboAppearance.vanishAnimation) {
                isContentPresented = false
            }

            try? await Task.sleep(for: AiboAppearance.vanishDuration + .milliseconds(50))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            stopClickThroughMonitoring()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                aiboAppearProgress = 0
            }
            isLaunchPortalPlaying = false
            detachLaunchPortalView()
            // Keep isContentPresented == false so the next show can animate in.
            hideTask = nil
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Development: play the cold-launch portal again without quitting.
    func replayLaunchPortal() {
        guard isVisible, isContentPresented, !isSuppressedForFullscreen, !isQuitPortalPlaying else { return }
        hideTask?.cancel()
        hideTask = nil
        startLaunchPortal()
    }

    /// Onboarding opening: hide bubbles, pin the slot at 40%/40%, then jump.
    /// Returns `false` when the panel is not ready or the shader cannot run.
    @discardableResult
    func playOnboardingEntrance() -> Bool {
        guard isVisible, isContentPresented, !isSuppressedForFullscreen, !isQuitPortalPlaying else { return false }
        hideTask?.cancel()
        hideTask = nil
        cancelDodge(persist: true)
        guard armLaunchPortal() else { return false }
        applyGeometryNow()
        placeAiboForOnboarding()
        attachLaunchPortalView()
        return true
    }

    func finishLaunchPortal() {
        guard isLaunchPortalPlaying else { return }
        let wasQuit = isQuitPortalPlaying
        let quitDone = quitPortalCompletion
        quitPortalCompletion = nil
        isQuitPortalPlaying = false
        portalPlayback = .forward
        // Metal completes outside the layout pass. Commit the normal panel
        // geometry with the reveal so no frame uses normal padding in a portal-sized window.
        // Quit must not reveal the live sprite: the last reverse frame is empty.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if wasQuit {
                isContentPresented = false
            }
            isLaunchPortalPlaying = false
            if !wasQuit {
                applyGeometryNow()
            }
            detachLaunchPortalView()
        }
        if wasQuit {
            panel?.orderOut(nil)
            quitDone?()
        }
    }

    /// Reverse of the launch jump. Returns `false` when Hide / fullscreen / Metal
    /// cannot play, so the caller should quit immediately.
    @discardableResult
    func playQuitPortal(completion: @escaping () -> Void) -> Bool {
        if isQuitPortalPlaying { return true }
        guard isVisible, isContentPresented, !isSuppressedForFullscreen else { return false }
        guard !isLaunchPortalPlaying else { return false }
        hideTask?.cancel()
        hideTask = nil
        guard canPlayLaunchPortal() else { return false }
        portalPlayback = .reverse
        isQuitPortalPlaying = true
        quitPortalCompletion = completion
        isLaunchPortalPlaying = true
        launchPortalGeneration += 1
        applyGeometryNow()
        guard attachLaunchPortalView() else {
            quitPortalCompletion = nil
            isQuitPortalPlaying = false
            portalPlayback = .forward
            isLaunchPortalPlaying = false
            applyGeometryNow()
            return false
        }
        return true
    }

    private func canPlayLaunchPortal() -> Bool {
        AiboLaunchPortalRenderer.shared != nil
            && AiboSpriteCache.shared.previewImage(
                for: AiboLibraryStore.shared.selectedRecord
            ) != nil
    }

    private func armLaunchPortalIfNeeded() {
        guard !hasPlayedLaunchPortal else { return }
        hasPlayedLaunchPortal = true
        _ = armLaunchPortal()
    }

    @discardableResult
    private func armLaunchPortal() -> Bool {
        guard canPlayLaunchPortal() else { return false }
        portalPlayback = .forward
        isLaunchPortalPlaying = true
        launchPortalGeneration += 1
        return true
    }

    private func startLaunchPortal() {
        cancelDodge(persist: true)
        guard armLaunchPortal() else { return }
        applyGeometryNow()
        attachLaunchPortalView()
    }

    private func attachLaunchPortalViewIfPlaying() {
        guard isLaunchPortalPlaying else { return }
        _ = attachLaunchPortalView()
    }

    @discardableResult
    private func attachLaunchPortalView() -> Bool {
        guard let rootView,
              let hostingView,
              let image = AiboSpriteCache.shared.previewImage(
                  for: AiboLibraryStore.shared.selectedRecord
              )
        else { return false }
        let record = AiboLibraryStore.shared.selectedRecord
        let view = launchPortalView ?? AiboLaunchPortalMetalView()
        launchPortalView = view
        if view.superview !== rootView {
            rootView.addSubview(view, positioned: .above, relativeTo: hostingView)
        }
        layoutLaunchPortalView()
        let hue = portalPlayback == .reverse
            ? AiboLaunchPortalStyle.exitHue
            : AiboLaunchPortalStyle.enterHue
        view.apply(
            image: image,
            aiboSize: laidOutAiboSize,
            usesNearest: record.pixelOptimizationEnabled && record.kind != .builtInDefault,
            generation: launchPortalGeneration,
            playback: portalPlayback,
            hue: hue,
            onCompleted: { [weak self] in
                self?.finishLaunchPortal()
            }
        )
        return true
    }

    private func layoutLaunchPortalView() {
        guard isLaunchPortalPlaying, let view = launchPortalView else { return }
        let aiboSize = laidOutAiboSize
        let canvas = AiboLaunchPortalTimeline.layout(aiboSize: aiboSize).canvas
        let center = laidOutAiboCenter
        view.frame = CGRect(
            x: center.x - canvas.width / 2,
            y: center.y - canvas.height / 2,
            width: canvas.width,
            height: canvas.height
        )
    }

    private func detachLaunchPortalView() {
        launchPortalView?.removeFromSuperview()
        launchPortalView = nil
    }

    /// Start/stop fullscreen detection (presentationOptions `.fullScreen` + Spaces type 4).
    ///
    /// When enabled:
    /// - Use `.moveToActiveSpace` (not `.canJoinAllSpaces`) so the aibo does not float over
    ///   the green-button fullscreen zoom animation; it leaves with its desktop Space.
    /// - No `.fullScreenAuxiliary`.
    /// - Same-Space fullscreen (e.g. some HTML5) still uses alpha suppress.
    func syncFullscreenPolicy() {
        if let panel {
            applyFullscreenCollectionBehavior(to: panel)
        }

        if AppSettings.shared.hideWhenFullscreen {
            fullscreenMonitor.start()
            handleFullscreenMonitorChange(fullscreenMonitor.isFullscreen)
        } else {
            fullscreenMonitor.stop()
            if isSuppressedForFullscreen {
                isSuppressedForFullscreen = false
            }
            applyFullscreenVisibility()
            if isVisible, isContentPresented {
                panel?.orderFrontRegardless()
            }
            PlaytimeStore.shared.noteVisibilityChanged()
        }
    }

    private var shouldPresentPanelOnScreen: Bool {
        isVisible && isContentPresented && !isSuppressedForFullscreen
    }

    /// Visible on the desktop (not Hide, not fullscreen-suppressed).
    var isPlaytimeActiveSurface: Bool { shouldPresentPanelOnScreen }

    private func applyFullscreenCollectionBehavior(to panel: AiboPanel) {
        if AppSettings.shared.hideWhenFullscreen {
            // One Space at a time. Reaffirm orderFront on desktop Space switches.
            panel.collectionBehavior = [.moveToActiveSpace, .stationary]
        } else {
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        }
    }

    private func handleFullscreenMonitorChange(_ isFullscreen: Bool) {
        guard AppSettings.shared.hideWhenFullscreen else { return }
        if isFullscreen {
            suppressForFullscreen()
        } else {
            unsuppressIfNeeded()
        }
    }

    /// Pull the aibo onto the active desktop Space after a Space switch.
    private func reaffirmPetVisibilityIfNeeded() {
        guard AppSettings.shared.hideWhenFullscreen else { return }
        guard isVisible, isContentPresented, !isSuppressedForFullscreen, let panel else { return }
        applyFullscreenCollectionBehavior(to: panel)
        // orderOut + orderFront forces moveToActiveSpace to relocate onto the new Space.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        applyFullscreenVisibility()
    }

    private func suppressForFullscreen() {
        cancelDodge(persist: true)
        isSuppressedForFullscreen = true
        applyFullscreenVisibility()
        // Leave the fullscreen Space entirely — do not float above the transition.
        panel?.orderOut(nil)
        PlaytimeStore.shared.noteVisibilityChanged()
    }

    private func unsuppressIfNeeded() {
        let wasSuppressed = isSuppressedForFullscreen
        isSuppressedForFullscreen = false
        defer { PlaytimeStore.shared.noteVisibilityChanged() }
        guard isVisible, isContentPresented, let panel else { return }
        applyFullscreenCollectionBehavior(to: panel)
        if wasSuppressed {
            panel.orderFrontRegardless()
        } else {
            reaffirmPetVisibilityIfNeeded()
            return
        }
        applyFullscreenVisibility()
    }

    /// Alpha suppress for same-Space fullscreen; Space fullscreen also orderOuts.
    private func applyFullscreenVisibility() {
        guard let panel else { return }
        if shouldPresentPanelOnScreen {
            panel.alphaValue = 1
            refreshClickThroughState()
        } else if isVisible, isSuppressedForFullscreen {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
        }
    }

    /// Keep content min==max at the managed frame so SwiftUI can't shrink the panel to 0.
    private func freezePanelSize() {
        guard let panel else { return }
        let minSize = aiboBlockMinimum(aiboSize: currentAiboSize)
        var frame = panel.frame
        if frame.width < minSize.width || frame.height < minSize.height {
            frame.size.width = max(frame.width, minSize.width)
            frame.size.height = max(frame.height, minSize.height)
            panel.setFrame(snappedPanelFrame(frame), display: false)
            applyContentFrame(frame.size)
        }
        pinContentSize(frame.size)
    }

    private func pinContentSize(_ size: NSSize) {
        guard let panel else { return }
        let safe = NSSize(width: max(size.width, 1), height: max(size.height, 1))
        panel.contentMinSize = safe
        panel.contentMaxSize = safe
    }

    private func applyContentFrame(_ size: NSSize) {
        let bounds = NSRect(origin: .zero, size: size)
        rootView?.frame = bounds
        hostingView?.frame = bounds
    }

    func refreshContent() {
        guard panel != nil else { return }
        let bubbleCount = AiboRuntime.shared.bubbleItems.count
        // Grow: defer one turn so we aren't inside SwiftUI/AppKit layout.
        // Shrink: wait for Pow poof (0.4s) so the cloud isn't clipped.
        if bubbleCount < laidOutBubbleCount {
            scheduleGeometryUpdate(after: .milliseconds(420))
        } else {
            scheduleGeometryUpdate(after: .zero)
        }
    }

    func syncLookDirection() {
        refreshLookDirection()
    }

    func syncMouseShakeDodgeEnabled() {
        guard !AppSettings.shared.mouseShakeDodgeEnabled else { return }
        shakeDetector.reset()
        cancelDodge(persist: true)
    }

    func updateHitTestImage() {
        let image = AiboSpriteCache.shared.previewImage(for: AiboLibraryStore.shared.selectedRecord)
        hostingView?.updateHitTestImage(image)
        AiboAppearance.invalidateDominantColorCache()
        #if DEBUG
        refreshHitRegionDebugOverlay()
        #endif
        refreshLookDirection()
    }

    /// Flush any pending resize and apply now. Caller must not be mid-layout.
    ///
    /// Desktop morph calls this from `AiboSwitchSignal.emit` (menu/button
    /// action, a different window than Settings) so the transparent panel
    /// already matches the union canvas before SwiftUI swaps in Metal.
    func syncGeometryNow() {
        cancelDodge(persist: true)
        applyGeometryNow()
    }

    /// URL / name fields in the tour need the floating panel to become key.
    func updateOnboardingKeyWindow() {
        guard let panel else { return }
        let allowed = OnboardingController.shared.allowsKeyWindow
        panel.allowsBecomingKey = allowed
        if allowed {
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }

    private func applyGeometryNow() {
        pendingGeometryTask?.cancel()
        pendingGeometryTask = nil
        let pinBubble = applyGeometryPreservingPetCenter()
        if !pinBubble {
            clampToVisibleScreen()
        }
    }

    private var pendingGeometryTask: Task<Void, Never>?

    /// Coalesce panel resizes off the current layout/update pass.
    /// Sync `setFrame(display:)` during SwiftUI updates triggers
    /// `layoutSubtreeIfNeeded` recursion warnings and Update Constraints crashes.
    private func scheduleGeometryUpdate(after delay: Duration) {
        pendingGeometryTask?.cancel()
        pendingGeometryTask = Task { @MainActor in
            if delay == .zero {
                await Task.yield()
            } else {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, panel != nil else { return }
            let pinBubble = applyGeometryPreservingPetCenter()
            if !pinBubble {
                clampToVisibleScreen()
            }
            pendingGeometryTask = nil
        }
    }

    /// Returns `true` when the onboarding bubble was pinned (do not clamp — that would drag it).
    @discardableResult
    private func applyGeometryPreservingPetCenter() -> Bool {
        guard let panel, !isRepositioningAibo else { return false }

        let items = AiboRuntime.shared.bubbleItems
        let placement = AiboLibraryStore.shared.selectedRecord.bubblePlacement
        let aiboSize = currentAiboSize
        let bubbleCount = effectiveBubbleCount(items)
        let pinBubble = shouldPinOnboardingBubble

        let oldFrame = panel.frame
        let oldAiboCenter = laidOutAiboCenter
        let aiboOnScreen = CGPoint(
            x: oldFrame.origin.x + oldAiboCenter.x,
            y: oldFrame.origin.y + oldAiboCenter.y
        )

        let newSize = panelSize(items: items, aiboSize: aiboSize, placement: placement)
        // Never allow a zero frame — SwiftUI + NSPanel constraint loops crash
        // with "more Update Constraints in Window passes than there are views".
        let minSize = aiboBlockMinimum(aiboSize: aiboSize)
        let safeSize = NSSize(
            width: max(newSize.width, minSize.width),
            height: max(newSize.height, minSize.height)
        )
        let newAiboCenter = aiboCenter(
            in: safeSize,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        if NSEqualSizes(safeSize, oldFrame.size),
           NSEqualSizes(aiboSize, laidOutAiboSize),
           placement == laidOutPlacement,
           bubbleCount == laidOutBubbleCount,
           onboardingLayoutID == laidOutOnboardingLayoutID,
           aiboBubbleSpacing == laidOutAiboBubbleSpacing,
           newAiboCenter == laidOutAiboCenter,
           isLaunchPortalPlaying == laidOutLaunchPortalPlaying
        {
            layoutLaunchPortalView()
            return pinBubble
        }

        var newFrame = oldFrame
        newFrame.size = safeSize
        if pinBubble,
           let oldAnchor = bubbleStackAnchor(
            panelSize: oldFrame.size,
            aiboSize: laidOutAiboSize,
            placement: laidOutPlacement,
            items: items,
            spacing: laidOutAiboBubbleSpacing
           ),
           let newAnchor = bubbleStackAnchor(
            panelSize: safeSize,
            aiboSize: aiboSize,
            placement: placement,
            items: items,
            spacing: aiboBubbleSpacing
           )
        {
            newFrame.origin.x = oldFrame.origin.x + oldAnchor.x - newAnchor.x
            newFrame.origin.y = oldFrame.origin.y + oldAnchor.y - newAnchor.y
        } else {
            newFrame.origin.x = aiboOnScreen.x - newAiboCenter.x
            newFrame.origin.y = aiboOnScreen.y - newAiboCenter.y
        }

        let frameToApply: NSRect
        if pinBubble {
            frameToApply = newFrame
        } else {
            frameToApply = snappedPanelFrame(
                newFrame,
                aiboSize: aiboSize,
                placement: placement,
                bubbleCount: bubbleCount
            )
        }

        // `display: false` avoids forcing layoutSubtreeIfNeeded inside an active layout pass.
        panel.setFrame(frameToApply, display: false)
        applyContentFrame(safeSize)
        pinContentSize(safeSize)
        laidOutBubbleCount = bubbleCount
        laidOutPlacement = placement
        laidOutAiboSize = aiboSize
        laidOutOnboardingLayoutID = onboardingLayoutID
        laidOutAiboBubbleSpacing = aiboBubbleSpacing
        updatePetHitRect(
            panelSize: safeSize,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        refreshLookDirection()
        layoutLaunchPortalView()
        return pinBubble
    }

    /// Same tour card, already laid out: keep that bubble on screen while size / gap change.
    private var shouldPinOnboardingBubble: Bool {
        !isLaunchPortalPlaying && !laidOutLaunchPortalPlaying
            && OnboardingController.shared.pinsBubbleDuringLayout
            && onboardingLayoutID == laidOutOnboardingLayoutID
    }

    private func aiboBlockMinimum(aiboSize: CGSize) -> NSSize {
        let insets = contentInsets
        return NSSize(
            width: max(aiboSize.width + insets.horizontal, 1),
            height: max(aiboSize.height + insets.vertical, 1)
        )
    }

    var spriteBackingScale: CGFloat {
        panel?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var currentAiboSize: CGSize {
        let signal = AiboSwitchSignal.shared
        if signal.locksDesktopSize, signal.canvasSize.width > 1 {
            return signal.canvasSize
        }
        return AiboSpriteDisplay.desktopSize(
            for: AiboLibraryStore.shared.selectedRecord,
            nominal: baseAiboSize * CGFloat(AiboLibraryStore.shared.selectedRecord.scalePercent / 100),
            backingScale: spriteBackingScale
        )
    }

    private func snappedPanelFrame(_ frame: NSRect) -> NSRect {
        snappedPanelFrame(
            frame,
            aiboSize: laidOutAiboSize,
            placement: laidOutPlacement,
            bubbleCount: laidOutBubbleCount
        )
    }

    private func snappedPanelFrame(
        _ frame: NSRect,
        aiboSize: CGSize,
        placement: BubblePlacement,
        bubbleCount: Int
    ) -> NSRect {
        guard AiboLibraryStore.shared.selectedRecord.pixelOptimizationEnabled else { return frame }
        let scale = spriteBackingScale
        guard scale > 0 else { return frame }
        let origin = aiboOrigin(
            in: frame.size,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        let sprite = CGPoint(x: frame.origin.x + origin.x, y: frame.origin.y + origin.y)
        let snapped = CGPoint(
            x: (sprite.x * scale).rounded(.toNearestOrAwayFromZero) / scale,
            y: (sprite.y * scale).rounded(.toNearestOrAwayFromZero) / scale
        )
        var result = frame
        result.origin.x += snapped.x - sprite.x
        result.origin.y += snapped.y - sprite.y
        return result
    }

    private func makePanel() -> AiboPanel {
        let placement = AiboLibraryStore.shared.selectedRecord.bubblePlacement
        let items = AiboRuntime.shared.bubbleItems
        let aiboSize = currentAiboSize
        let bubbleCount = effectiveBubbleCount(items)
        let initialSize = panelSize(items: items, aiboSize: aiboSize, placement: placement)
        let minSize = aiboBlockMinimum(aiboSize: aiboSize)
        let safeInitial = NSSize(
            width: max(initialSize.width, minSize.width),
            height: max(initialSize.height, minSize.height)
        )
        let panel = AiboPanel(contentRect: NSRect(origin: .zero, size: safeInitial))

        // Hosting view must NOT be the window contentView — see AiboPanelRootView.
        let rootView = AiboPanelRootView(frame: NSRect(origin: .zero, size: safeInitial))
        rootView.wantsLayer = true
        rootView.layer?.masksToBounds = false
        let hostingView = PassThroughHostingView(
            rootView: AiboView(),
            hitTestImage: AiboSpriteCache.shared.previewImage(for: AiboLibraryStore.shared.selectedRecord)
        )
        hostingView.sizingOptions = []
        hostingView.clipsToBounds = false
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        hostingView.frame = rootView.bounds
        hostingView.autoresizingMask = [.width, .height]
        rootView.addSubview(hostingView)
        #if DEBUG
        let debugOverlay = HitRegionDebugOverlay(frame: rootView.bounds)
        debugOverlay.autoresizingMask = [.width, .height]
        rootView.addSubview(debugOverlay)
        hitRegionDebugOverlay = debugOverlay
        #endif
        panel.contentView = rootView

        self.rootView = rootView
        self.hostingView = hostingView
        pinContentSize(safeInitial)
        laidOutBubbleCount = bubbleCount
        laidOutPlacement = placement
        laidOutAiboSize = aiboSize
        updatePetHitRect(
            panelSize: safeInitial,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        applyFullscreenCollectionBehavior(to: panel)
        return panel
    }

    private func panelSize(
        items: [StatusBubbleItem],
        aiboSize: CGSize,
        placement: BubblePlacement
    ) -> NSSize {
        let insets = contentInsets
        let aiboBlockWidth = aiboSize.width + insets.horizontal
        let aiboBlockHeight = aiboSize.height + insets.vertical
        let bubbleCount = effectiveBubbleCount(items)
        guard bubbleCount > 0 else {
            return NSSize(width: max(aiboBlockWidth, 1), height: max(aiboBlockHeight, 1))
        }

        let heights = items.map(estimatedBubbleHeight(for:))
        let stackHeight =
            heights.reduce(0, +)
            + CGFloat(max(0, bubbleCount - 1)) * bubbleStackSpacing

        switch placement {
        case .top, .bottom:
            return NSSize(
                width: max(aiboBlockWidth, bubbleMaxWidth + insets.horizontal),
                height: max(
                    aiboBlockHeight + stackHeight + aiboBubbleSpacing + panelBubbleSlack
                        + onboardingActionPillsHeight,
                    1
                )
            )
        case .left, .right:
            // Near-pet bubble centered with pet; older bubbles grow upward.
            // Size only to row + stackAbove — do NOT mirror empty space below
            // (halfAbove * 2 left a dead purple zone that blocked the desktop).
            let nearHeight = heights.last ?? bubbleEstimatedHeight
            let aboveHeights = heights.dropLast()
            let stackAbove =
                aboveHeights.reduce(0, +)
                + CGFloat(max(0, aboveHeights.count - 1)) * bubbleStackSpacing
            let rowHeight = max(aiboSize.height, nearHeight)
            let pills = onboardingActionPillsHeight
            return NSSize(
                width: max(aiboBlockWidth + bubbleMaxWidth + aiboBubbleSpacing + panelBubbleSlack, 1),
                height: max(insets.vertical + rowHeight + stackAbove + pills, 1)
            )
        }
    }

    /// Approximate rendered bubble height for panel sizing (header + capsule/CTA row).
    private func estimatedBubbleHeight(for item: StatusBubbleItem) -> CGFloat {
        if item.kind == .onboarding {
            return estimatedOnboardingClusterHeight(for: item)
        }
        let contentWidth = bubbleMaxWidth - bubbleContentPadding * 2 - bubbleArrowSlack
        let trailingReserve: CGFloat = item.isAwaitingApproval ? 24 : 0
        let capsuleWidth = bubbleCapsuleWidthEstimate
            + (item.planProgress == nil ? 0 : bubbleCapsulePlanProgressExtra)
        let textWidth = contentWidth - capsuleWidth - bubbleRowSpacing - trailingReserve
        let font = NSFont.systemFont(ofSize: 14)
        let textHeight = ceil(
            (item.text as NSString).boundingRect(
                with: NSSize(width: max(1, textWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        let statusRowHeight = max(bubbleStatusLineHeight, textHeight)
        var height = bubbleContentPadding * 2 + statusRowHeight
        let hasHeader: Bool = switch item.kind {
        case .webhook, .warning:
            true
        case .agent:
            !(item.projectName ?? "").isEmpty || !(item.modelName ?? "").isEmpty
        case .onboarding:
            true
        }
        if hasHeader {
            height += bubbleHeaderLineHeight + bubbleSectionSpacing
        }
        return max(bubbleEstimatedHeight, height + bubbleArrowSlack)
    }

    /// Welcome copy wraps, and action pills sit 8pt under the bubble.
    private func estimatedOnboardingClusterHeight(for item: StatusBubbleItem) -> CGFloat {
        let contentWidth = bubbleMaxWidth - bubbleContentPadding * 2 - bubbleArrowSlack
        let font = NSFont.systemFont(ofSize: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = bubbleStatusLineHeight
        paragraph.maximumLineHeight = bubbleStatusLineHeight
        let textHeight = ceil(
            (item.text as NSString).boundingRect(
                with: NSSize(width: max(1, contentWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraph,
                ]
            ).height
        )
        var height = bubbleContentPadding * 2 + max(bubbleStatusLineHeight, textHeight)
        height += bubbleHeaderLineHeight + bubbleSectionSpacing
        height += bubbleArrowSlack
        let tour = OnboardingController.shared
        if tour.isActive, tour.step == .chooseAibo {
            height += OnboardingChrome.chooseAiboExtraHeight(
                phase: tour.choosePhase,
                hasError: tour.errorMessage != nil
            )
        } else if tour.isActive, tour.step == .agentHook {
            height += OnboardingChrome.agentHookExtraHeight(hasError: tour.errorMessage != nil)
        }
        return max(bubbleEstimatedHeight, height)
    }

    private var onboardingLayoutID: String {
        let tour = OnboardingController.shared
        guard tour.isActive else { return "" }
        let hooks = AiboRuntime.shared
        return "\(tour.step.rawValue).\(tour.choosePhase.rawValue).\(tour.errorMessage != nil).\(hooks.cursorHooksInstalled).\(hooks.codexHooksInstalled)"
    }

    private func updatePetHitRect(
        panelSize: NSSize,
        aiboSize: CGSize,
        placement: BubblePlacement,
        bubbleCount: Int
    ) {
        let origin = aiboOrigin(
            in: panelSize,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        laidOutAiboFrame = CGRect(origin: origin, size: aiboSize)
        laidOutLaunchPortalPlaying = isLaunchPortalPlaying
        hostingView?.aiboHitRect = laidOutAiboFrame
        hostingView?.bubbleHitRects = bubbleHitRects(
            panelSize: panelSize,
            aiboSize: aiboSize,
            placement: placement,
            items: AiboRuntime.shared.bubbleItems
        )
        #if DEBUG
        refreshHitRegionDebugOverlay()
        #endif
        refreshClickThroughState()
    }

    /// Bottom-left of the near-aibo bubble stack in panel coords (AppKit origin).
    private func bubbleStackAnchor(
        panelSize: NSSize,
        aiboSize: CGSize,
        placement: BubblePlacement,
        items: [StatusBubbleItem],
        spacing: CGFloat
    ) -> CGPoint? {
        bubbleHitRects(
            panelSize: panelSize,
            aiboSize: aiboSize,
            placement: placement,
            items: items,
            spacing: spacing
        ).first.map(\.origin)
    }

    /// Bottom-left union rects for bubble stacks so empty panel chrome can click through.
    private func bubbleHitRects(
        panelSize: NSSize,
        aiboSize: CGSize,
        placement: BubblePlacement,
        items: [StatusBubbleItem],
        spacing: CGFloat? = nil
    ) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let gap = spacing ?? aiboBubbleSpacing
        let insets = contentInsets
        let origin = aiboOrigin(
            in: panelSize,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: items.count
        )
        let heights = items.map(estimatedBubbleHeight(for:))
        let stackHeight =
            heights.reduce(0, +)
            + CGFloat(max(0, items.count - 1)) * bubbleStackSpacing
        let contentWidth = panelSize.width - insets.horizontal

        switch placement {
        case .top:
            let width = min(bubbleMaxWidth, contentWidth)
            let x = insets.leading + (contentWidth - width) / 2
            let y = origin.y + aiboSize.height + gap
            return [CGRect(x: x, y: y, width: width, height: stackHeight)]
        case .bottom:
            let width = min(bubbleMaxWidth, contentWidth)
            let x = insets.leading + (contentWidth - width) / 2
            let y = origin.y - gap - stackHeight
            return [CGRect(x: x, y: y, width: width, height: stackHeight)]
        case .right:
            let x = origin.x + aiboSize.width + gap
            let width = min(bubbleMaxWidth, max(0, panelSize.width - x - insets.trailing))
            let nearHeight = heights.last ?? bubbleEstimatedHeight
            let aboveHeights = heights.dropLast()
            let stackAbove =
                aboveHeights.reduce(0, +)
                + CGFloat(max(0, aboveHeights.count - 1)) * bubbleStackSpacing
            let nearBottom = sideBubbleNearBottom(
                aiboOriginY: origin.y,
                aiboHeight: aiboSize.height,
                nearHeight: nearHeight
            )
            let pills = onboardingActionPillsHeight
            return [CGRect(
                x: x,
                y: nearBottom - pills,
                width: width,
                height: nearHeight + stackAbove + pills
            )]
        case .left:
            let width = min(bubbleMaxWidth, max(0, origin.x - gap - insets.leading))
            let x = origin.x - gap - width
            let nearHeight = heights.last ?? bubbleEstimatedHeight
            let aboveHeights = heights.dropLast()
            let stackAbove =
                aboveHeights.reduce(0, +)
                + CGFloat(max(0, aboveHeights.count - 1)) * bubbleStackSpacing
            let nearBottom = sideBubbleNearBottom(
                aiboOriginY: origin.y,
                aiboHeight: aiboSize.height,
                nearHeight: nearHeight
            )
            let pills = onboardingActionPillsHeight
            return [CGRect(
                x: x,
                y: nearBottom - pills,
                width: width,
                height: nearHeight + stackAbove + pills
            )]
        }
    }

    /// Side row is vertically centered: near-bubble midpoint matches aibo midpoint.
    private func sideBubbleNearBottom(
        aiboOriginY: CGFloat,
        aiboHeight: CGFloat,
        nearHeight: CGFloat
    ) -> CGFloat {
        let aiboCenterY = aiboOriginY + aiboHeight / 2
        return aiboCenterY - nearHeight / 2
    }

    #if DEBUG
    private func refreshHitRegionDebugOverlay() {
        guard let overlay = hitRegionDebugOverlay, let hostingView else { return }
        overlay.contentInsets = contentInsets
        overlay.aiboHitRect = hostingView.aiboHitRect
        overlay.bubbleHitRects = hostingView.bubbleHitRects
        if hostingView.aiboHitRect.isNull == false {
            overlay.opaqueAiboImage = hostingView.opaqueAiboDebugImage(size: hostingView.aiboHitRect.size)
        } else {
            overlay.opaqueAiboImage = nil
        }
        overlay.isOverlayEnabled = showHitRegionDebug
        overlay.needsDisplay = true
    }
    #endif

    /// Pet image center inside the panel (AppKit coords, origin bottom-left).
    private func aiboCenter(
        in panelSize: NSSize,
        aiboSize: CGSize,
        placement: BubblePlacement,
        bubbleCount: Int
    ) -> CGPoint {
        let origin = aiboOrigin(
            in: panelSize,
            aiboSize: aiboSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        return CGPoint(x: origin.x + aiboSize.width / 2, y: origin.y + aiboSize.height / 2)
    }

    private func aiboOrigin(
        in panelSize: NSSize,
        aiboSize: CGSize,
        placement: BubblePlacement,
        bubbleCount: Int
    ) -> CGPoint {
        let insets = contentInsets
        let contentWidth = panelSize.width - insets.horizontal
        if bubbleCount == 0 {
            switch placement {
            case .top:
                return CGPoint(
                    x: insets.leading + (contentWidth - aiboSize.width) / 2,
                    y: insets.bottom
                )
            case .bottom:
                return CGPoint(
                    x: insets.leading + (contentWidth - aiboSize.width) / 2,
                    y: panelSize.height - insets.top - aiboSize.height
                )
            case .left:
                return CGPoint(
                    x: panelSize.width - insets.trailing - aiboSize.width,
                    y: insets.bottom
                )
            case .right:
                return CGPoint(
                    x: insets.leading,
                    y: insets.bottom
                )
            }
        }
        switch placement {
        case .top:
            // SwiftUI: bubble stack above, pet below → pet near AppKit bottom.
            return CGPoint(
                x: insets.leading + (contentWidth - aiboSize.width) / 2,
                y: insets.bottom
            )
        case .bottom:
            // Pet above → near AppKit top.
            return CGPoint(
                x: insets.leading + (contentWidth - aiboSize.width) / 2,
                y: panelSize.height - insets.top - aiboSize.height
            )
        case .left, .right:
            // Vertically center the pet with the near bubble. Skip / Continue
            // hang below the bubble and take extra panel space, not this row.
            let items = AiboRuntime.shared.bubbleItems
            let nearHeight = items.last.map(estimatedBubbleHeight(for:)) ?? bubbleEstimatedHeight
            let rowHeight = max(aiboSize.height, nearHeight)
            let y = insets.bottom + onboardingActionPillsHeight
                + (rowHeight - aiboSize.height) / 2
            if placement == .left {
                return CGPoint(x: panelSize.width - insets.trailing - aiboSize.width, y: y)
            }
            return CGPoint(x: insets.leading, y: y)
        }
    }

    /// Floating NSPanel keeps the whole frame in the hit path even when content
    /// `hitTest` returns nil — toggle `ignoresMouseEvents` from mouse moves
    /// (event-driven; global monitor covers the ignore=true gap).
    private func startClickThroughMonitoringIfNeeded() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.refreshClickThroughState()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshClickThroughState()
            }
        }
    }

    private func stopClickThroughMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        panel?.ignoresMouseEvents = false
    }

    private func refreshDragAction(deltaX: CGFloat) {
        pendingDragDeltaX += deltaX
        guard abs(pendingDragDeltaX) >= Self.dragDirectionThreshold else { return }
        let action: AiboUserAction = pendingDragDeltaX < 0 ? .dragLeft : .dragRight
        pendingDragDeltaX = 0
        let next = AiboActionSettings.shared.sprite(for: action)
        guard dragActionSprite != next else { return }
        dragActionSprite = next
        // Event-tracking mode doesn't pump `.default`; drain it once so SwiftUI
        // can swap the sprite layer while the drag is still in progress.
        RunLoop.current.run(mode: .default, before: Date())
    }

    private func refreshClickThroughState() {
        refreshLookDirection()
        if !isRepositioningAibo {
            evaluateMouseShake()
        }
        if isPetDragging { return }
        guard let panel else { return }
        guard isVisible, isContentPresented, shouldPresentPanelOnScreen, !isSuppressedForFullscreen else {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        guard panel.frame.contains(screenPoint) else {
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }
            return
        }

        guard let content = panel.contentView else { return }
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let pointInContent = content.convert(windowPoint, from: nil)
        let shouldIgnore = content.hitTest(pointInContent) == nil
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    private func startObservingScreenChangesIfNeeded() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        let settings = AppSettings.shared
        if settings.restoreLastAiboPosition,
           let x = settings.savedAiboCenterXPercent,
           let y = settings.savedAiboCenterYPercent
        {
            placeAtRelativePosition(
                xPercent: x,
                yPercent: y,
                on: screenForSavedAiboPosition()
            )
        }
        clampToVisibleScreen()
    }

    private func placeInitially() {
        if OnboardingController.shared.isActive {
            placeAiboForOnboarding()
            return
        }
        let settings = AppSettings.shared
        if settings.restoreLastAiboPosition,
           let x = settings.savedAiboCenterXPercent,
           let y = settings.savedAiboCenterYPercent
        {
            placeAtRelativePosition(
                xPercent: x,
                yPercent: y,
                on: screenForSavedAiboPosition()
            )
            clampToVisibleScreen()
        } else {
            placeAtDefaultCorner()
        }
    }

    private func placeAtDefaultCorner() {
        guard let panel else { return }
        guard let screen = NSScreen.aiboScreenContaining(NSEvent.mouseLocation) ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visible.maxX - frame.width - screenPadding
        frame.origin.y = visible.minY + screenPadding
        panel.setFrame(snappedPanelFrame(frame), display: false)
    }

    func placeAiboForOnboarding() {
        placeAiboAtRelativePosition(
            xPercent: OnboardingChrome.aiboCenterXPercent,
            yPercent: OnboardingChrome.aiboCenterYPercent
        )
    }

    func placeAiboAtRelativePosition(xPercent: Double, yPercent: Double) {
        placeAtRelativePosition(
            xPercent: xPercent,
            yPercent: yPercent,
            on: screenForSavedAiboPosition()
        )
        clampToVisibleScreen()
    }

    /// Screen the saved percents were taken on. Do not use `NSScreen.main` first:
    /// a menu-bar extra often reports the laptop as main even when aibo lives on an external.
    private func screenForSavedAiboPosition() -> NSScreen? {
        NSScreen.aiboScreen(withDisplayUUID: AppSettings.shared.savedAiboPositionScreenUUID)
            ?? NSScreen.aiboScreenContaining(NSEvent.mouseLocation)
            ?? NSScreen.aiboScreenContaining(aiboScreenCenter())
            ?? panel?.screen
            ?? NSScreen.main
    }

    /// Place so the aibo center lands at `(xPercent, yPercent)` of that screen's visible frame.
    private func placeAtRelativePosition(xPercent: Double, yPercent: Double, on screen: NSScreen?) {
        guard let panel else { return }
        guard let screen else { return }

        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }

        let aiboOnScreen = CGPoint(
            x: visible.minX + CGFloat(xPercent) * visible.width,
            y: visible.minY + CGFloat(yPercent) * visible.height
        )
        let centerInPanel = laidOutAiboCenter

        var frame = panel.frame
        frame.origin.x = aiboOnScreen.x - centerInPanel.x
        frame.origin.y = aiboOnScreen.y - centerInPanel.y
        panel.setFrame(snappedPanelFrame(frame), display: false)
    }

    /// Keep the *pet* inside the padded visible frame. Stacked bubbles may
    /// extend off-screen — clamping the whole panel would shove the aibo up/down.
    private func clampToVisibleScreen() {
        guard let panel, !isRepositioningAibo else { return }
        let centerInPanel = laidOutAiboCenter
        var aiboOnScreen = CGPoint(
            x: panel.frame.origin.x + centerInPanel.x,
            y: panel.frame.origin.y + centerInPanel.y
        )
        let screen = NSScreen.aiboScreenContaining(aiboOnScreen) ?? panel.screen ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = max(frame.size.width, 1)
        frame.size.height = max(frame.size.height, 1)

        // Shrink padding if the visible area is tiny so min ≤ max still holds.
        let padX = min(screenPadding, max(0, visible.width / 2 - 1))
        let padY = min(screenPadding, max(0, visible.height / 2 - 1))
        let minX = visible.minX + padX
        let maxX = visible.maxX - padX
        let minY = visible.minY + padY
        let maxY = visible.maxY - padY

        if aiboOnScreen.x < minX {
            aiboOnScreen.x = minX
        } else if aiboOnScreen.x > maxX {
            aiboOnScreen.x = maxX
        }
        if aiboOnScreen.y < minY {
            aiboOnScreen.y = minY
        } else if aiboOnScreen.y > maxY {
            aiboOnScreen.y = maxY
        }

        frame.origin.x = aiboOnScreen.x - centerInPanel.x
        frame.origin.y = aiboOnScreen.y - centerInPanel.y

        panel.setFrame(snappedPanelFrame(frame), display: false)
        applyContentFrame(frame.size)
        pinContentSize(frame.size)
    }

    private func beginPetDrag() {
        isPetDragging = true
        pendingDragDeltaX = 0
        dragActionSprite = nil
    }

    private func endPetDrag() {
        isPetDragging = false
        pendingDragDeltaX = 0
        if dragActionSprite != nil {
            dragActionSprite = nil
        }
    }

    /// Move the panel from opaque-pixel mouse-down. Waits on `nextEvent` (not a
    /// timer) so horizontal direction can drive the mapped run animation.
    ///
    /// Pins the aibo to the original grab offset each event (not incremental
    /// `origin + delta`). Sprite swaps drain `.default` and can shift the frame;
    /// re-pinning after that keeps the cursor on the same pixel.
    func performPetDrag(with startEvent: NSEvent) {
        guard let panel, !isLaunchPortalPlaying else { return }
        cancelDodge(persist: false)
        beginPetDrag()
        let grabOffset = grabOffsetFromAibo(for: startEvent)
        var lastMouseX = NSEvent.mouseLocation.x
        while true {
            guard let event = panel.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            if event.type == .leftMouseUp { break }
            let mouseX = NSEvent.mouseLocation.x
            let dx = mouseX - lastMouseX
            lastMouseX = mouseX
            pinAiboToMouse(grabOffset: grabOffset)
            refreshDragAction(deltaX: dx)
            pinAiboToMouse(grabOffset: grabOffset)
        }
        endPetDrag()
        persistRelativePositionNow()
    }

    /// Cursor minus aibo-center at mouse-down, in screen points.
    private func grabOffsetFromAibo(for event: NSEvent) -> CGPoint {
        let mouse = screenPoint(for: event)
        let aibo = aiboScreenCenter()
        return CGPoint(x: mouse.x - aibo.x, y: mouse.y - aibo.y)
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func aiboScreenCenter() -> CGPoint {
        guard let panel else { return .zero }
        let center = laidOutAiboCenter
        return CGPoint(
            x: panel.frame.origin.x + center.x,
            y: panel.frame.origin.y + center.y
        )
    }

    private func pinAiboToMouse(grabOffset: CGPoint) {
        let mouse = NSEvent.mouseLocation
        moveAiboScreenCenter(
            to: CGPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y)
        )
    }

    private func moveAiboScreenCenter(to point: CGPoint) {
        guard let panel else { return }
        let center = laidOutAiboCenter
        let origin = snappedPanelFrame(
            NSRect(
                origin: NSPoint(x: point.x - center.x, y: point.y - center.y),
                size: panel.frame.size
            )
        ).origin
        panel.setFrameOrigin(origin)
    }

    /// Write the current pet-center fractions of the screen visible frame.
    /// Call after the user finishes dragging, and on quit.
    func persistRelativePositionNow() {
        guard let panel else { return }
        let centerInPanel = laidOutAiboCenter
        let aiboOnScreen = CGPoint(
            x: panel.frame.origin.x + centerInPanel.x,
            y: panel.frame.origin.y + centerInPanel.y
        )
        let screen = NSScreen.aiboScreenContaining(aiboOnScreen) ?? panel.screen ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }

        let xPercent = Double((aiboOnScreen.x - visible.minX) / visible.width)
        let yPercent = Double((aiboOnScreen.y - visible.minY) / visible.height)
        AppSettings.shared.saveAiboCenterRelativePosition(
            xPercent: xPercent,
            yPercent: yPercent,
            screenUUID: screen.aiboDisplayUUID
        )
        refreshLookDirection()
    }

    #if DEBUG
    func debugTriggerDodge() {
        cancelDodge(persist: false)
        beginDodge()
    }
    #endif

    private func evaluateMouseShake() {
        guard AppSettings.shared.mouseShakeDodgeEnabled else { return }
        guard canBeginDodge, NSEvent.pressedMouseButtons == 0 else { return }
        let config = shakeConfig
        shakeDetector.config = config
        let mouse = NSEvent.mouseLocation
        let triggered = shakeDetector.push(
            x: mouse.x,
            time: ProcessInfo.processInfo.systemUptime,
            inProximity: isMouseInAiboProximity(padding: config.proximityPadding)
        )
        guard triggered else { return }
        beginDodge()
    }

    private var canBeginDodge: Bool {
        isVisible
            && isContentPresented
            && shouldPresentPanelOnScreen
            && !isSuppressedForFullscreen
            && !isLaunchPortalPlaying
            && !isQuitPortalPlaying
            && !OnboardingController.shared.isActive
            && panel != nil
    }

    private func isMouseInAiboProximity(padding: Double) -> Bool {
        guard let panel, laidOutAiboFrame.width > 0, laidOutAiboFrame.height > 0 else {
            return false
        }
        let pad = CGFloat(padding)
        let rect = laidOutAiboFrame.insetBy(dx: -pad, dy: -pad)
        let screenRect = CGRect(
            x: panel.frame.origin.x + rect.minX,
            y: panel.frame.origin.y + rect.minY,
            width: rect.width,
            height: rect.height
        )
        return screenRect.contains(NSEvent.mouseLocation)
    }

    private func beginDodge() {
        guard canBeginDodge, !isPetDragging else { return }
        let config = shakeConfig
        let from = aiboScreenCenter()
        let screen = NSScreen.aiboScreenContaining(from) ?? panel?.screen ?? NSScreen.main
        guard let screen else { return }
        let span = max(laidOutAiboSize.width, laidOutAiboSize.height)
        guard span > 1 else { return }
        let distance = span * config.dodgeDistanceFactor
        let to = MouseShakeDodge.target(
            from: from,
            in: screen.visibleFrame,
            distance: distance,
            padding: screenPadding
        )
        guard hypot(to.x - from.x, to.y - from.y) >= 1 else { return }

        shakeDetector.markTriggered(at: ProcessInfo.processInfo.systemUptime)
        isPetDodging = true
        let dx = to.x - from.x
        if dx > 0.5 {
            dragActionSprite = AiboActionSettings.shared.sprite(for: .dragRight)
        } else if dx < -0.5 {
            dragActionSprite = AiboActionSettings.shared.sprite(for: .dragLeft)
        }

        dodgeAnimator.start(
            screen: screen,
            duration: config.dodgeDuration,
            onProgress: { [weak self] progress in
                guard let self else { return }
                self.moveAiboScreenCenter(
                    to: MouseShakeDodge.interpolate(from: from, to: to, progress: progress)
                )
            },
            onCompleted: { [weak self] in
                guard let self else { return }
                self.moveAiboScreenCenter(to: to)
                self.finishDodge()
            }
        )
    }

    private func finishDodge() {
        isPetDodging = false
        if dragActionSprite != nil {
            dragActionSprite = nil
        }
        persistRelativePositionNow()
        refreshClickThroughState()
    }

    private func cancelDodge(persist: Bool) {
        guard isPetDodging || dodgeAnimator.isRunning else { return }
        dodgeAnimator.cancel()
        isPetDodging = false
        if dragActionSprite != nil {
            dragActionSprite = nil
        }
        if persist {
            persistRelativePositionNow()
        }
    }

    /// Bucketed pointer look. Only assigns when the 22.5° cell changes.
    private func refreshLookDirection() {
        if isPetDodging {
            if lookDirection != nil { lookDirection = nil }
            return
        }
        if AppSettings.shared.disableMouseTracking {
            if lookDirection != nil { lookDirection = nil }
            return
        }
        guard isVisible, isContentPresented, !isSuppressedForFullscreen, let panel else {
            return
        }
        let record = AiboLibraryStore.shared.selectedRecord
        guard AiboSpriteCache.shared.supportsLookDirections(for: record) else {
            if lookDirection != nil { lookDirection = nil }
            return
        }

        let mouse = NSEvent.mouseLocation
        let centerInPanel = laidOutAiboCenter
        let aiboOnScreen = CGPoint(
            x: panel.frame.origin.x + centerInPanel.x,
            y: panel.frame.origin.y + centerInPanel.y
        )
        let next = PetdexLookDirection.resolve(
            deltaX: Double(mouse.x - aiboOnScreen.x),
            deltaYDown: Double(aiboOnScreen.y - mouse.y),
            deadzone: Double(max(laidOutAiboSize.width, laidOutAiboSize.height) * 0.5)
        )
        if lookDirection != next {
            lookDirection = next
        }
    }
}
