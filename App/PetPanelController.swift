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

    private let baseSize = NSSize(width: 240, height: 160)
    private let screenPadding: CGFloat = 24

    private init() {}

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        refreshContent()
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

    func refreshContent() {
        let text = PetRuntime.shared.bubbleText
        let rootView = PetView(bubbleText: text)
        if let hostingView {
            hostingView.rootView = rootView
        }
        guard let panel else { return }

        let height: CGFloat = text == nil ? 120 : 180
        var frame = panel.frame
        frame.size = NSSize(width: baseSize.width, height: height)
        panel.setContentSize(frame.size)
        repositionIfNeeded()
    }

    private func makePanel() -> PetPanel {
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: baseSize))
        let hostingView = PassThroughHostingView(
            rootView: PetView(bubbleText: PetRuntime.shared.bubbleText),
            hitTestImage: NSImage(named: "DefaultPet")
        )
        hostingView.frame = NSRect(origin: .zero, size: baseSize)
        panel.contentView = hostingView
        self.hostingView = hostingView
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
        frame.origin.x = visible.maxX - frame.width - screenPadding
        frame.origin.y = visible.minY + screenPadding

        if !screen.frame.intersects(frame) {
            frame.origin.x = visible.maxX - frame.width - screenPadding
            frame.origin.y = visible.minY + screenPadding
        }

        panel.setFrame(frame, display: true)
    }
}
