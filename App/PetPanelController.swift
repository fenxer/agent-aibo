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
    private var screenObserver: NSObjectProtocol?
    private var hasPlacedInitially = false
    private var hideTask: Task<Void, Never>?
    /// Last layout we sized/positioned for — used to keep the pet fixed on screen.
    private var laidOutBubbleCount = 0
    private var laidOutPlacement: BubblePlacement = .top
    private var laidOutPetSize: CGFloat = 96

    private let basePetSize: CGFloat = 96
    private let contentPadding: CGFloat = 8
    private let screenPadding: CGFloat = 24
    private let bubbleMaxWidth: CGFloat = 320
    private let bubbleEstimatedHeight: CGFloat = 88
    private let bubbleStackSpacing: CGFloat = 4
    private let bubbleContentPadding: CGFloat = 12
    private let bubbleHeaderLineHeight: CGFloat = 15
    private let bubbleSectionSpacing: CGFloat = 12
    private let bubbleStatusLineHeight: CGFloat = 24
    private let bubbleCapsuleWidthEstimate: CGFloat = 88
    private let bubbleArrowSlack: CGFloat = 6
    private let bubbleRowSpacing: CGFloat = 8

    private init() {}

    func show() {
        hideTask?.cancel()
        hideTask = nil

        let panel = panel ?? makePanel()
        self.panel = panel
        // Menu / launch path — safe to size synchronously (not inside a layout pass).
        applyGeometryNow()
        if !hasPlacedInitially {
            placeAtDefaultCorner()
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
        panel.orderFrontRegardless()
        isVisible = true
        startObservingScreenChangesIfNeeded()

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
        max(petSize + contentPadding * 2, 1)
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
        let hostingView = PassThroughHostingView(
            rootView: PetView(),
            hitTestImage: PetSpriteCache.shared.previewImage(for: PetLibraryStore.shared.selectedRecord)
                ?? NSImage(named: "DefaultPet")
        )
        hostingView.sizingOptions = []
        hostingView.clipsToBounds = false
        hostingView.frame = rootView.bounds
        hostingView.autoresizingMask = [.width, .height]
        rootView.addSubview(hostingView)
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
        return panel
    }

    private func panelSize(
        items: [StatusBubbleItem],
        petSize: CGFloat,
        placement: BubblePlacement
    ) -> NSSize {
        let petBlock = petSize + contentPadding * 2
        let bubbleCount = items.count
        guard bubbleCount > 0 else {
            return NSSize(width: max(petBlock, 1), height: max(petBlock, 1))
        }

        let heights = items.map(estimatedBubbleHeight(for:))
        let stackHeight =
            heights.reduce(0, +)
            + CGFloat(max(0, bubbleCount - 1)) * bubbleStackSpacing

        switch placement {
        case .top, .bottom:
            return NSSize(
                width: max(petBlock, bubbleMaxWidth + contentPadding * 2),
                height: max(petBlock + stackHeight + 20, 1)
            )
        case .left, .right:
            // Near-pet bubble stays vertically centered with the pet; older
            // bubbles grow upward — panel must leave room above the pet center.
            // `items` are newest-first; near-pet is last.
            let nearHeight = heights.last ?? bubbleEstimatedHeight
            let aboveHeights = heights.dropLast()
            let stackAbove =
                aboveHeights.reduce(0, +)
                + CGFloat(max(0, aboveHeights.count - 1)) * bubbleStackSpacing
            let halfAbove = contentPadding + stackAbove + nearHeight / 2
            return NSSize(
                width: max(petBlock + bubbleMaxWidth + 20, 1),
                height: max(petBlock, halfAbove * 2, 1)
            )
        }
    }

    /// Approximate rendered bubble height for panel sizing (header + capsule row).
    private func estimatedBubbleHeight(for item: StatusBubbleItem) -> CGFloat {
        let contentWidth = bubbleMaxWidth - bubbleContentPadding * 2 - bubbleArrowSlack
        let textWidth = contentWidth - bubbleCapsuleWidthEstimate - bubbleRowSpacing
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
        case .webhook:
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
    }

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
        let pad = contentPadding
        if bubbleCount == 0 {
            return CGPoint(
                x: (panelSize.width - petSize) / 2,
                y: (panelSize.height - petSize) / 2
            )
        }
        switch placement {
        case .top:
            // SwiftUI: bubble stack above, pet below → pet near AppKit bottom.
            return CGPoint(x: (panelSize.width - petSize) / 2, y: pad)
        case .bottom:
            // Pet above → near AppKit top.
            return CGPoint(x: (panelSize.width - petSize) / 2, y: panelSize.height - pad - petSize)
        case .left:
            // Pet on trailing side.
            return CGPoint(x: panelSize.width - pad - petSize, y: (panelSize.height - petSize) / 2)
        case .right:
            // Pet on leading side.
            return CGPoint(x: pad, y: (panelSize.height - petSize) / 2)
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
                self?.clampToVisibleScreen()
            }
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

    private func clampToVisibleScreen() {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        var frame = panel.frame

        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        frame.size.width = max(frame.size.width, 1)
        frame.size.height = max(frame.size.height, 1)

        if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
        }
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }

        panel.setFrame(frame, display: false)
        applyContentFrame(frame.size)
        pinContentSize(frame.size)
    }
}
