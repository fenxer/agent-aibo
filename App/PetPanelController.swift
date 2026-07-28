import AppKit
import SwiftUI

@MainActor
@Observable
final class PetPanelController {
    static let shared = PetPanelController()

    private(set) var isVisible = false

    private var panel: PetPanel?
    private var hostingView: PassThroughHostingView<PetView>?
    private var screenObserver: NSObjectProtocol?
    private var hasPlacedInitially = false
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
        let panel = panel ?? makePanel()
        self.panel = panel
        refreshContent()
        if !hasPlacedInitially {
            placeAtDefaultCorner()
            hasPlacedInitially = true
        } else {
            clampToVisibleScreen()
        }
        panel.orderFrontRegardless()
        isVisible = true
        startObservingScreenChangesIfNeeded()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func refreshContent() {
        let items = PetRuntime.shared.bubbleItems
        let placement = AppSettings.shared.bubblePlacement
        let petSize = currentPetSize
        let bubbleCount = items.count
        guard let panel else { return }

        // Snapshot before rootView update — hosting view must not drive window size.
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

        let rootView = PetView(bubbleItems: items, placement: placement, petSize: petSize)
        if let hostingView {
            hostingView.rootView = rootView
        }

        let newSize = panelSize(items: items, petSize: petSize, placement: placement)
        let newPetCenter = petCenter(
            in: newSize,
            petSize: petSize,
            placement: placement,
            bubbleCount: bubbleCount
        )

        var newFrame = oldFrame
        newFrame.size = newSize
        newFrame.origin.x = petOnScreen.x - newPetCenter.x
        newFrame.origin.y = petOnScreen.y - newPetCenter.y
        panel.setFrame(newFrame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: newSize)

        laidOutBubbleCount = bubbleCount
        laidOutPlacement = placement
        laidOutPetSize = petSize

        updatePetHitRect(
            panelSize: newSize,
            petSize: petSize,
            placement: placement,
            bubbleCount: bubbleCount
        )
        clampToVisibleScreen()
    }

    private var currentPetSize: CGFloat {
        basePetSize * CGFloat(AppSettings.shared.petScalePercent / 100)
    }

    private func makePanel() -> PetPanel {
        let placement = AppSettings.shared.bubblePlacement
        let items = PetRuntime.shared.bubbleItems
        let petSize = currentPetSize
        let initialSize = panelSize(items: items, petSize: petSize, placement: placement)
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: initialSize))
        let hostingView = PassThroughHostingView(
            rootView: PetView(bubbleItems: items, placement: placement, petSize: petSize),
            hitTestImage: NSImage(named: "DefaultPet")
        )
        // We size the panel explicitly; don't let SwiftUI intrinsic size move the window.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        panel.contentView = hostingView
        self.hostingView = hostingView
        laidOutBubbleCount = items.count
        laidOutPlacement = placement
        laidOutPetSize = petSize
        updatePetHitRect(
            panelSize: initialSize,
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
        panel.setFrame(frame, display: true)
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

        panel.setFrame(frame, display: true)
    }
}
