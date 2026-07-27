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

    private let petSize: CGFloat = 96
    private let contentPadding: CGFloat = 8
    private let screenPadding: CGFloat = 24
    private let bubbleMaxWidth: CGFloat = 220
    private let bubbleEstimatedHeight: CGFloat = 52

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
        let text = PetRuntime.shared.bubbleText
        let placement = AppSettings.shared.bubblePlacement
        let rootView = PetView(bubbleText: text, placement: placement)
        if let hostingView {
            hostingView.rootView = rootView
        }
        guard let panel else { return }

        let newSize = panelSize(hasBubble: text != nil, placement: placement)
        let oldFrame = panel.frame

        // Keep the pet's center stable when bubble layout/size changes.
        var newFrame = oldFrame
        newFrame.size = newSize
        newFrame.origin.x = oldFrame.midX - newSize.width / 2
        newFrame.origin.y = oldFrame.midY - newSize.height / 2
        panel.setFrame(newFrame, display: true)

        updatePetHitRect(panelSize: newSize, placement: placement, hasBubble: text != nil)
        clampToVisibleScreen()
    }

    private func makePanel() -> PetPanel {
        let placement = AppSettings.shared.bubblePlacement
        let initialSize = panelSize(hasBubble: false, placement: placement)
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: initialSize))
        let hostingView = PassThroughHostingView(
            rootView: PetView(
                bubbleText: PetRuntime.shared.bubbleText,
                placement: placement
            ),
            hitTestImage: NSImage(named: "DefaultPet")
        )
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        panel.contentView = hostingView
        self.hostingView = hostingView
        updatePetHitRect(panelSize: initialSize, placement: placement, hasBubble: false)
        return panel
    }

    private func panelSize(hasBubble: Bool, placement: BubblePlacement) -> NSSize {
        let petBlock = petSize + contentPadding * 2
        guard hasBubble else {
            return NSSize(width: petBlock, height: petBlock)
        }

        switch placement {
        case .top, .bottom:
            return NSSize(
                width: max(petBlock, bubbleMaxWidth + contentPadding * 2),
                height: petBlock + bubbleEstimatedHeight + 20
            )
        case .left, .right:
            return NSSize(
                width: petBlock + bubbleMaxWidth + 20,
                height: max(petBlock, bubbleEstimatedHeight + contentPadding * 2 + 24)
            )
        }
    }

    private func updatePetHitRect(
        panelSize: NSSize,
        placement: BubblePlacement,
        hasBubble: Bool
    ) {
        let pad = contentPadding
        let x: CGFloat
        let y: CGFloat

        if !hasBubble {
            x = (panelSize.width - petSize) / 2
            y = (panelSize.height - petSize) / 2
        } else {
            switch placement {
            case .top:
                // SwiftUI: bubble above, pet below → pet near AppKit bottom.
                x = (panelSize.width - petSize) / 2
                y = pad
            case .bottom:
                // Pet above → near AppKit top.
                x = (panelSize.width - petSize) / 2
                y = panelSize.height - pad - petSize
            case .left:
                // Pet on trailing side.
                x = panelSize.width - pad - petSize
                y = (panelSize.height - petSize) / 2
            case .right:
                // Pet on leading side.
                x = pad
                y = (panelSize.height - petSize) / 2
            }
        }

        hostingView?.petHitRect = CGRect(x: x, y: y, width: petSize, height: petSize)
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
