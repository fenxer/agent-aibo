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

    private let petSize: CGFloat = 96
    private let contentPadding: CGFloat = 8
    private let screenPadding: CGFloat = 24
    private let bubbleMaxWidth: CGFloat = 220
    private let bubbleEstimatedHeight: CGFloat = 52
    private let bubbleStackSpacing: CGFloat = 4

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
        let bubbleCount = items.count
        guard let panel else { return }

        // Snapshot before rootView update — hosting view must not drive window size.
        let oldFrame = panel.frame
        let oldPetCenter = petCenter(
            in: oldFrame.size,
            placement: laidOutPlacement,
            bubbleCount: laidOutBubbleCount
        )
        let petOnScreen = CGPoint(
            x: oldFrame.origin.x + oldPetCenter.x,
            y: oldFrame.origin.y + oldPetCenter.y
        )

        let rootView = PetView(bubbleItems: items, placement: placement)
        if let hostingView {
            hostingView.rootView = rootView
        }

        let newSize = panelSize(bubbleCount: bubbleCount, placement: placement)
        let newPetCenter = petCenter(
            in: newSize,
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

        updatePetHitRect(panelSize: newSize, placement: placement, bubbleCount: bubbleCount)
        clampToVisibleScreen()
    }

    private func makePanel() -> PetPanel {
        let placement = AppSettings.shared.bubblePlacement
        let items = PetRuntime.shared.bubbleItems
        let initialSize = panelSize(bubbleCount: items.count, placement: placement)
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: initialSize))
        let hostingView = PassThroughHostingView(
            rootView: PetView(bubbleItems: items, placement: placement),
            hitTestImage: NSImage(named: "DefaultPet")
        )
        // We size the panel explicitly; don't let SwiftUI intrinsic size move the window.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        panel.contentView = hostingView
        self.hostingView = hostingView
        laidOutBubbleCount = items.count
        laidOutPlacement = placement
        updatePetHitRect(panelSize: initialSize, placement: placement, bubbleCount: items.count)
        return panel
    }

    private func panelSize(bubbleCount: Int, placement: BubblePlacement) -> NSSize {
        let petBlock = petSize + contentPadding * 2
        guard bubbleCount > 0 else {
            return NSSize(width: petBlock, height: petBlock)
        }

        let stackHeight =
            CGFloat(bubbleCount) * bubbleEstimatedHeight
            + CGFloat(max(0, bubbleCount - 1)) * bubbleStackSpacing

        switch placement {
        case .top, .bottom:
            return NSSize(
                width: max(petBlock, bubbleMaxWidth + contentPadding * 2),
                height: petBlock + stackHeight + 20
            )
        case .left, .right:
            // Near-pet bubble stays vertically centered with the pet; older
            // bubbles grow upward — panel must leave room above the pet center.
            let stackAbove =
                CGFloat(max(0, bubbleCount - 1)) * bubbleEstimatedHeight
                + CGFloat(max(0, bubbleCount - 2)) * bubbleStackSpacing
            let halfAbove = contentPadding + stackAbove + bubbleEstimatedHeight / 2
            return NSSize(
                width: petBlock + bubbleMaxWidth + 20,
                height: max(petBlock, halfAbove * 2)
            )
        }
    }

    private func updatePetHitRect(
        panelSize: NSSize,
        placement: BubblePlacement,
        bubbleCount: Int
    ) {
        let origin = petOrigin(in: panelSize, placement: placement, bubbleCount: bubbleCount)
        hostingView?.petHitRect = CGRect(origin: origin, size: CGSize(width: petSize, height: petSize))
    }

    /// Pet image center inside the panel (AppKit coords, origin bottom-left).
    private func petCenter(
        in panelSize: NSSize,
        placement: BubblePlacement,
        bubbleCount: Int
    ) -> CGPoint {
        let origin = petOrigin(in: panelSize, placement: placement, bubbleCount: bubbleCount)
        return CGPoint(x: origin.x + petSize / 2, y: origin.y + petSize / 2)
    }

    private func petOrigin(
        in panelSize: NSSize,
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
