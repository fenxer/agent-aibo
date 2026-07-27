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

    private let baseWidth: CGFloat = 240
    private let petSize: CGFloat = 96
    private let contentPadding: CGFloat = 8
    private let screenPadding: CGFloat = 24

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
        let rootView = PetView(bubbleText: text)
        if let hostingView {
            hostingView.rootView = rootView
        }
        guard let panel else { return }

        let height: CGFloat = text == nil ? 120 : 180
        let newSize = NSSize(width: baseWidth, height: height)
        let oldFrame = panel.frame

        // Keep the pet's bottom-center stable when the bubble changes panel height.
        var newFrame = oldFrame
        newFrame.size = newSize
        newFrame.origin.x = oldFrame.midX - newSize.width / 2
        newFrame.origin.y = oldFrame.minY
        panel.setFrame(newFrame, display: true)

        updatePetHitRect(panelHeight: height)
        clampToVisibleScreen()
    }

    private func makePanel() -> PetPanel {
        let initialSize = NSSize(width: baseWidth, height: 120)
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: initialSize))
        let hostingView = PassThroughHostingView(
            rootView: PetView(bubbleText: PetRuntime.shared.bubbleText),
            hitTestImage: NSImage(named: "DefaultPet")
        )
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        panel.contentView = hostingView
        self.hostingView = hostingView
        updatePetHitRect(panelHeight: initialSize.height)
        return panel
    }

    private func updatePetHitRect(panelHeight: CGFloat) {
        let rect = CGRect(
            x: (baseWidth - petSize) / 2,
            y: contentPadding,
            width: petSize,
            height: petSize
        )
        hostingView?.petHitRect = rect
        _ = panelHeight
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
