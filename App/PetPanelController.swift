import AppKit
import SwiftUI

@MainActor
@Observable
final class PetPanelController {
    static let shared = PetPanelController()

    private(set) var isVisible = false

    private var panel: PetPanel?
    private var screenObserver: NSObjectProtocol?

    private let panelSize = NSSize(width: 120, height: 120)
    private let screenPadding: CGFloat = 24

    private init() {}

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        repositionIfNeeded()
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

    private func makePanel() -> PetPanel {
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        let hostingView = PassThroughHostingView(
            rootView: PetView(),
            hitTestImage: NSImage(named: "DefaultPet")
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
        return panel
    }

    private func startObservingScreenChangesIfNeeded() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionIfNeeded()
            }
        }
    }

    private func repositionIfNeeded() {
        guard let panel else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size = panelSize
        frame.origin.x = visible.maxX - panelSize.width - screenPadding
        frame.origin.y = visible.minY + screenPadding

        // If the panel somehow left all screens, snap back into the main visible frame.
        if !screen.frame.intersects(frame) {
            frame.origin.x = visible.maxX - panelSize.width - screenPadding
            frame.origin.y = visible.minY + screenPadding
        }

        panel.setFrame(frame, display: true)
    }
}
