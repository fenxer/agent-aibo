import AppKit
import SwiftUI

@MainActor
@Observable
final class PetPanelController {
    static let shared = PetPanelController()

    private(set) var isVisible = false
    /// When false, the pet sprite vanishes (Pow); panel `orderOut` follows after the effect.
    private(set) var isContentPresented = true
    /// 0 = above / squashed, 1 = settled. Explicit show motion (not Pow boing).
    private(set) var petAppearProgress: CGFloat = 1

    private var panel: PetPanel?
    private var rootView: PetPanelRootView?
    private var hostingView: PassThroughHostingView<PetView>?
    #if DEBUG
    private var hitRegionDebugOverlay: HitRegionDebugOverlay?
    /// Development → Hit Regions: paint panel / padding / petHitRect / opaque drag mask.
    var showHitRegionDebug = true {
        didSet { refreshHitRegionDebugOverlay() }
    }
    #endif
    private var screenObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private let fullscreenMonitor = FullscreenSpaceMonitor()
    /// True while hide-when-fullscreen is suppressing the panel (not user Hide Pet).
    private var isSuppressedForFullscreen = false
    private var hasPlacedInitially = false
    private var hideTask: Task<Void, Never>?
    /// Last layout we sized/positioned for — used to keep the pet fixed on screen.
    private var laidOutBubbleCount = 0
    private var laidOutPlacement: BubblePlacement = .top
    private var laidOutPetSize: CGFloat = 96

    private let basePetSize: CGFloat = 96
    private let screenPadding: CGFloat = 24
    private let bubbleMaxWidth: CGFloat = 320
    private let bubbleEstimatedHeight: CGFloat = 88
    private let bubbleStackSpacing: CGFloat = 4
    /// Matches `PetView.petBubbleSpacing` (pet ↔ bubble stack gap).
    private let petBubbleSpacing: CGFloat = 6
    private let bubbleContentPadding: CGFloat = 12
    private let bubbleHeaderLineHeight: CGFloat = 15
    private let bubbleSectionSpacing: CGFloat = 12
    private let bubbleStatusLineHeight: CGFloat = 24
    private let bubbleCapsuleWidthEstimate: CGFloat = 88
    private let bubbleArrowSlack: CGFloat = 6
    private let bubbleRowSpacing: CGFloat = 8

    private var contentInsets: PetContentInsets {
        PetContentInsets.current(musicNotesEnabled: AppSettings.shared.musicNotesEnabled)
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
        hideTask?.cancel()
        hideTask = nil

        let panel = panel ?? makePanel()
        self.panel = panel
        applyFullscreenCollectionBehavior(to: panel)
        // Menu / launch path — safe to size synchronously (not inside a layout pass).
        applyGeometryNow()
        if !hasPlacedInitially {
            placeInitially()
            hasPlacedInitially = true
        } else {
            clampToVisibleScreen()
        }

        // First launch: already presented. After hide: re-insert with identity, then
        // spring petAppearProgress (Pow `.boing` GeometryEffect collapses this panel).
        let shouldBoing = !isContentPresented
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if shouldBoing {
                petAppearProgress = 0
                isContentPresented = true
            } else {
                petAppearProgress = 1
                isContentPresented = true
            }
        }

        freezePanelSize()
        isVisible = true
        startObservingScreenChangesIfNeeded()
        startClickThroughMonitoringIfNeeded()
        syncFullscreenPolicy()

        // Keep the panel ordered in. When hide-when-fullscreen is on we use
        // moveToActiveSpace (not canJoinAllSpaces) so the pet leaves with its
        // desktop during the fullscreen zoom instead of floating over it.
        panel.orderFrontRegardless()
        applyFullscreenVisibility()

        if shouldBoing {
            hideTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(PetAppearance.boingAnimation) {
                    petAppearProgress = 1
                }
                hideTask = nil
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        hideTask?.cancel()

        hideTask = Task { @MainActor in
            // Let the menu dismiss finish — mutating the panel during that layout pass
            // triggers NSHostingView constraint recursion.
            await Task.yield()
            guard !Task.isCancelled else { return }

            freezePanelSize()
            // Do not setFrame / resize here. Vanish must run against a stable panel size.
            withAnimation(PetAppearance.vanishAnimation) {
                isContentPresented = false
            }

            try? await Task.sleep(for: PetAppearance.vanishDuration + .milliseconds(50))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            stopClickThroughMonitoring()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                petAppearProgress = 0
            }
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

    /// Start/stop fullscreen detection (presentationOptions `.fullScreen` + Spaces type 4).
    ///
    /// When enabled:
    /// - Use `.moveToActiveSpace` (not `.canJoinAllSpaces`) so the pet does not float over
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
        }
    }

    private var shouldPresentPanelOnScreen: Bool {
        isVisible && isContentPresented && !isSuppressedForFullscreen
    }

    private func applyFullscreenCollectionBehavior(to panel: PetPanel) {
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

    /// Pull the pet onto the active desktop Space after a Space switch.
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
        isSuppressedForFullscreen = true
        applyFullscreenVisibility()
        // Leave the fullscreen Space entirely — do not float above the transition.
        panel?.orderOut(nil)
    }

    private func unsuppressIfNeeded() {
        let wasSuppressed = isSuppressedForFullscreen
        isSuppressedForFullscreen = false
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
        let minSide = petBlockMinimum(petSize: currentPetSize)
        var frame = panel.frame
        if frame.width < minSide || frame.height < minSide {
            frame.size.width = max(frame.width, minSide)
            frame.size.height = max(frame.height, minSide)
            panel.setFrame(frame, display: false)
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
        let bubbleCount = PetRuntime.shared.bubbleItems.count
        // Grow: defer one turn so we aren't inside SwiftUI/AppKit layout.
        // Shrink: wait for Pow poof (0.4s) so the cloud isn't clipped.
        if bubbleCount < laidOutBubbleCount {
            scheduleGeometryUpdate(after: .milliseconds(420))
        } else {
            scheduleGeometryUpdate(after: .zero)
        }
    }

    func updateHitTestImage() {
        let image = PetSpriteCache.shared.previewImage(for: PetLibraryStore.shared.selectedRecord)
            ?? NSImage(named: "DefaultPet")
        hostingView?.updateHitTestImage(image)
        PetAppearance.invalidateDominantColorCache()
        #if DEBUG
        refreshHitRegionDebugOverlay()
        #endif
    }

    /// Flush any pending resize and apply now. Caller must not be mid-layout.
    private func applyGeometryNow() {
        pendingGeometryTask?.cancel()
        pendingGeometryTask = nil
        applyGeometryPreservingPetCenter()
        clampToVisibleScreen()
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
            applyGeometryPreservingPetCenter()
            clampToVisibleScreen()
            pendingGeometryTask = nil
        }
    }

    private func applyGeometryPreservingPetCenter() {
        guard let panel else { return }

        let items = PetRuntime.shared.bubbleItems
        let placement = AppSettings.shared.bubblePlacement
        let petSize = currentPetSize
        let bubbleCount = items.count

        let oldFrame = panel.frame
        let oldPetCenter = petCenter(
            in: oldFrame.size,
            petSize: laidOutPetSize,
            placement: laidOutPlacement,
            bubbleCount: laidOutBubbleCount
        )
        let petOnScreen = CGPoint(
            x: oldFrame.origin.x + oldPetCenter.x,
            y: oldFrame.origin.y + oldPetCenter.y
        )

        let newSize = panelSize(items: items, petSize: petSize, placement: placement)
        // Never allow a zero frame — SwiftUI + NSPanel constraint loops crash
        // with "more Update Constraints in Window passes than there are views".
        let safeSize = NSSize(
            width: max(newSize.width, petBlockMinimum(petSize: petSize)),
            height: max(newSize.height, petBlockMinimum(petSize: petSize))
        )
        let newPetCenter = petCenter(
            in: safeSize,
            petSize: petSize,
            placement: placement,
            bubbleCount: bubbleCount
        )

        var newFrame = oldFrame
        newFrame.size = safeSize
        newFrame.origin.x = petOnScreen.x - newPetCenter.x
        newFrame.origin.y = petOnScreen.y - newPetCenter.y

        // `display: false` avoids forcing layoutSubtreeIfNeeded inside an active layout pass.
        panel.setFrame(newFrame, display: false)
        applyContentFrame(safeSize)
        pinContentSize(safeSize)
        laidOutBubbleCount = bubbleCount
        laidOutPlacement = placement
        laidOutPetSize = petSize
        updatePetHitRect(
            panelSize: safeSize,
            petSize: petSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
    }

    private func petBlockMinimum(petSize: CGFloat) -> CGFloat {
        let insets = contentInsets
        return max(petSize + max(insets.horizontal, insets.vertical), 1)
    }

    private var currentPetSize: CGFloat {
        basePetSize * CGFloat(AppSettings.shared.petScalePercent / 100)
    }

    private func makePanel() -> PetPanel {
        let placement = AppSettings.shared.bubblePlacement
        let items = PetRuntime.shared.bubbleItems
        let petSize = currentPetSize
        let initialSize = panelSize(items: items, petSize: petSize, placement: placement)
        let safeInitial = NSSize(
            width: max(initialSize.width, petBlockMinimum(petSize: petSize)),
            height: max(initialSize.height, petBlockMinimum(petSize: petSize))
        )
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: safeInitial))

        // Hosting view must NOT be the window contentView — see PetPanelRootView.
        let rootView = PetPanelRootView(frame: NSRect(origin: .zero, size: safeInitial))
        rootView.wantsLayer = true
        rootView.layer?.masksToBounds = false
        let hostingView = PassThroughHostingView(
            rootView: PetView(),
            hitTestImage: PetSpriteCache.shared.previewImage(for: PetLibraryStore.shared.selectedRecord)
                ?? NSImage(named: "DefaultPet")
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
        laidOutBubbleCount = items.count
        laidOutPlacement = placement
        laidOutPetSize = petSize
        updatePetHitRect(
            panelSize: safeInitial,
            petSize: petSize,
            placement: placement,
            bubbleCount: items.count
        )
        applyFullscreenCollectionBehavior(to: panel)
        return panel
    }

    private func panelSize(
        items: [StatusBubbleItem],
        petSize: CGFloat,
        placement: BubblePlacement
    ) -> NSSize {
        let insets = contentInsets
        let petBlockWidth = petSize + insets.horizontal
        let petBlockHeight = petSize + insets.vertical
        let bubbleCount = items.count
        guard bubbleCount > 0 else {
            return NSSize(width: max(petBlockWidth, 1), height: max(petBlockHeight, 1))
        }

        let heights = items.map(estimatedBubbleHeight(for:))
        let stackHeight =
            heights.reduce(0, +)
            + CGFloat(max(0, bubbleCount - 1)) * bubbleStackSpacing

        switch placement {
        case .top, .bottom:
            return NSSize(
                width: max(petBlockWidth, bubbleMaxWidth + insets.horizontal),
                height: max(petBlockHeight + stackHeight + 20, 1)
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
            let rowHeight = max(petSize, nearHeight)
            return NSSize(
                width: max(petBlockWidth + bubbleMaxWidth + 20, 1),
                height: max(insets.vertical + rowHeight + stackAbove, 1)
            )
        }
    }

    /// Approximate rendered bubble height for panel sizing (header + capsule/CTA row).
    private func estimatedBubbleHeight(for item: StatusBubbleItem) -> CGFloat {
        let contentWidth = bubbleMaxWidth - bubbleContentPadding * 2 - bubbleArrowSlack
        let trailingReserve: CGFloat = item.isAwaitingApproval ? 24 : 0
        let textWidth = contentWidth - bubbleCapsuleWidthEstimate - bubbleRowSpacing - trailingReserve
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
        }
        if hasHeader {
            height += bubbleHeaderLineHeight + bubbleSectionSpacing
        }
        return max(bubbleEstimatedHeight, height + bubbleArrowSlack)
    }

    private func updatePetHitRect(
        panelSize: NSSize,
        petSize: CGFloat,
        placement: BubblePlacement,
        bubbleCount: Int
    ) {
        let origin = petOrigin(
            in: panelSize,
            petSize: petSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        hostingView?.petHitRect = CGRect(origin: origin, size: CGSize(width: petSize, height: petSize))
        hostingView?.bubbleHitRects = bubbleHitRects(
            panelSize: panelSize,
            petSize: petSize,
            placement: placement,
            items: PetRuntime.shared.bubbleItems
        )
        #if DEBUG
        refreshHitRegionDebugOverlay()
        #endif
        refreshClickThroughState()
    }

    /// Bottom-left union rects for bubble stacks so empty panel chrome can click through.
    private func bubbleHitRects(
        panelSize: NSSize,
        petSize: CGFloat,
        placement: BubblePlacement,
        items: [StatusBubbleItem]
    ) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let insets = contentInsets
        let origin = petOrigin(
            in: panelSize,
            petSize: petSize,
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
            let y = origin.y + petSize + petBubbleSpacing
            return [CGRect(x: x, y: y, width: width, height: stackHeight)]
        case .bottom:
            let width = min(bubbleMaxWidth, contentWidth)
            let x = insets.leading + (contentWidth - width) / 2
            let y = origin.y - petBubbleSpacing - stackHeight
            return [CGRect(x: x, y: y, width: width, height: stackHeight)]
        case .right:
            let x = origin.x + petSize
            let width = min(bubbleMaxWidth, max(0, panelSize.width - x - insets.trailing))
            let nearHeight = heights.last ?? bubbleEstimatedHeight
            let aboveHeights = heights.dropLast()
            let stackAbove =
                aboveHeights.reduce(0, +)
                + CGFloat(max(0, aboveHeights.count - 1)) * bubbleStackSpacing
            let petCenterY = origin.y + petSize / 2
            let nearBottom = petCenterY - nearHeight / 2
            return [CGRect(x: x, y: nearBottom, width: width, height: nearHeight + stackAbove)]
        case .left:
            let width = min(bubbleMaxWidth, max(0, origin.x - insets.leading))
            let x = origin.x - width
            let nearHeight = heights.last ?? bubbleEstimatedHeight
            let aboveHeights = heights.dropLast()
            let stackAbove =
                aboveHeights.reduce(0, +)
                + CGFloat(max(0, aboveHeights.count - 1)) * bubbleStackSpacing
            let petCenterY = origin.y + petSize / 2
            let nearBottom = petCenterY - nearHeight / 2
            return [CGRect(x: x, y: nearBottom, width: width, height: nearHeight + stackAbove)]
        }
    }

    #if DEBUG
    private func refreshHitRegionDebugOverlay() {
        guard let overlay = hitRegionDebugOverlay, let hostingView else { return }
        overlay.contentInsets = contentInsets
        overlay.petHitRect = hostingView.petHitRect
        overlay.bubbleHitRects = hostingView.bubbleHitRects
        if hostingView.petHitRect.isNull == false {
            overlay.opaquePetImage = hostingView.opaquePetDebugImage(size: hostingView.petHitRect.size)
        } else {
            overlay.opaquePetImage = nil
        }
        overlay.isOverlayEnabled = showHitRegionDebug
        overlay.needsDisplay = true
    }
    #endif

    /// Pet image center inside the panel (AppKit coords, origin bottom-left).
    private func petCenter(
        in panelSize: NSSize,
        petSize: CGFloat,
        placement: BubblePlacement,
        bubbleCount: Int
    ) -> CGPoint {
        let origin = petOrigin(
            in: panelSize,
            petSize: petSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        return CGPoint(x: origin.x + petSize / 2, y: origin.y + petSize / 2)
    }

    private func petOrigin(
        in panelSize: NSSize,
        petSize: CGFloat,
        placement: BubblePlacement,
        bubbleCount: Int
    ) -> CGPoint {
        let insets = contentInsets
        let contentWidth = panelSize.width - insets.horizontal
        if bubbleCount == 0 {
            switch placement {
            case .top:
                return CGPoint(
                    x: insets.leading + (contentWidth - petSize) / 2,
                    y: insets.bottom
                )
            case .bottom:
                return CGPoint(
                    x: insets.leading + (contentWidth - petSize) / 2,
                    y: panelSize.height - insets.top - petSize
                )
            case .left:
                return CGPoint(
                    x: panelSize.width - insets.trailing - petSize,
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
                x: insets.leading + (contentWidth - petSize) / 2,
                y: insets.bottom
            )
        case .bottom:
            // Pet above → near AppKit top.
            return CGPoint(
                x: insets.leading + (contentWidth - petSize) / 2,
                y: panelSize.height - insets.top - petSize
            )
        case .left, .right:
            // Bottom-aligned row: pet shares a vertical center with the near bubble.
            let items = PetRuntime.shared.bubbleItems
            let nearHeight = items.last.map(estimatedBubbleHeight(for:)) ?? bubbleEstimatedHeight
            let rowHeight = max(petSize, nearHeight)
            let y = insets.bottom + (rowHeight - petSize) / 2
            if placement == .left {
                return CGPoint(x: panelSize.width - insets.trailing - petSize, y: y)
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

    private func refreshClickThroughState() {
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
        if settings.restoreLastPetPosition,
           let x = settings.savedPetCenterXPercent,
           let y = settings.savedPetCenterYPercent
        {
            placeAtRelativePosition(xPercent: x, yPercent: y)
        }
        clampToVisibleScreen()
    }

    private func placeInitially() {
        let settings = AppSettings.shared
        if settings.restoreLastPetPosition,
           let x = settings.savedPetCenterXPercent,
           let y = settings.savedPetCenterYPercent
        {
            placeAtRelativePosition(xPercent: x, yPercent: y)
            clampToVisibleScreen()
        } else {
            placeAtDefaultCorner()
        }
    }

    private func placeAtDefaultCorner() {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }

        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visible.maxX - frame.width - screenPadding
        frame.origin.y = visible.minY + screenPadding
        panel.setFrame(frame, display: false)
    }

    /// Place so the pet center lands at `(xPercent, yPercent)` of the screen visible frame.
    private func placeAtRelativePosition(xPercent: Double, yPercent: Double) {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }

        let petOnScreen = CGPoint(
            x: visible.minX + CGFloat(xPercent) * visible.width,
            y: visible.minY + CGFloat(yPercent) * visible.height
        )
        let centerInPanel = petCenter(
            in: panel.frame.size,
            petSize: laidOutPetSize,
            placement: laidOutPlacement,
            bubbleCount: laidOutBubbleCount
        )

        var frame = panel.frame
        frame.origin.x = petOnScreen.x - centerInPanel.x
        frame.origin.y = petOnScreen.y - centerInPanel.y
        panel.setFrame(frame, display: false)
    }

    /// Keep the *pet* inside the padded visible frame. Stacked bubbles may
    /// extend off-screen — clamping the whole panel would shove the pet up/down.
    private func clampToVisibleScreen() {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = max(frame.size.width, 1)
        frame.size.height = max(frame.size.height, 1)

        let centerInPanel = petCenter(
            in: frame.size,
            petSize: laidOutPetSize,
            placement: laidOutPlacement,
            bubbleCount: laidOutBubbleCount
        )
        var petOnScreen = CGPoint(
            x: frame.origin.x + centerInPanel.x,
            y: frame.origin.y + centerInPanel.y
        )

        // Shrink padding if the visible area is tiny so min ≤ max still holds.
        let padX = min(screenPadding, max(0, visible.width / 2 - 1))
        let padY = min(screenPadding, max(0, visible.height / 2 - 1))
        let minX = visible.minX + padX
        let maxX = visible.maxX - padX
        let minY = visible.minY + padY
        let maxY = visible.maxY - padY

        if petOnScreen.x < minX {
            petOnScreen.x = minX
        } else if petOnScreen.x > maxX {
            petOnScreen.x = maxX
        }
        if petOnScreen.y < minY {
            petOnScreen.y = minY
        } else if petOnScreen.y > maxY {
            petOnScreen.y = maxY
        }

        frame.origin.x = petOnScreen.x - centerInPanel.x
        frame.origin.y = petOnScreen.y - centerInPanel.y

        panel.setFrame(frame, display: false)
        applyContentFrame(frame.size)
        pinContentSize(frame.size)
    }

    /// Write the current pet-center fractions of the screen visible frame.
    /// Call after the user finishes dragging, and on quit.
    func persistRelativePositionNow() {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }

        let centerInPanel = petCenter(
            in: panel.frame.size,
            petSize: laidOutPetSize,
            placement: laidOutPlacement,
            bubbleCount: laidOutBubbleCount
        )
        let petOnScreen = CGPoint(
            x: panel.frame.origin.x + centerInPanel.x,
            y: panel.frame.origin.y + centerInPanel.y
        )
        let xPercent = Double((petOnScreen.x - visible.minX) / visible.width)
        let yPercent = Double((petOnScreen.y - visible.minY) / visible.height)
        AppSettings.shared.savePetCenterRelativePosition(xPercent: xPercent, yPercent: yPercent)
    }
}
