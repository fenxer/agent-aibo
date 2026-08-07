import AppKit
import SwiftUI

/// Settings-window plumbing that SwiftUI does not cover: insert `.resizable`
/// once per window, restore the persisted height on first attach, and save it
/// after live resize.
///
/// The scene declares `.windowResizability(.contentMinSize)` and the root view
/// reports a fixed width plus `maxHeight: .infinity`, so SwiftUI's computed
/// extrema are already correct (`contentMaxSize` is unbounded). But the
/// `Settings` scene still creates the window without `.resizable` in its
/// `styleMask` (macOS 26, SO 79532884), so we repair the mask once on attach.
///
/// Do **not** re-assert `styleMask` or content size extrema from
/// `NSWindow.didUpdateNotification`: that fires every frame while a Form
/// scrolls, fights SwiftUI's own extrema sync (`NSHostingView.
/// updateWindowContentSizeExtremaIfNecessary` → `setStyleMask` →
/// `NSThemeFrame _updateButtons`), spikes CPU, and rebuilds the traffic-light
/// buttons (visible green-light flicker). With stable extrema SwiftUI never
/// touches the mask after creation, so a one-time repair is enough.
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> Helper {
        let view = Helper()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: Helper, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: Helper, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Helper: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?

        func attach(to window: NSWindow?) {
            guard let window, window !== observedWindow else { return }
            detach()
            observedWindow = window
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
            applySavedHeight(to: window)
            // First attach / new window instance — activate + key (menu / SettingsLink).
            SettingsNavigator.shared.handleSettingsWindowAppeared(window)

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.persistHeight(of: window)
                }
            }
        }

        func detach() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            observedWindow = nil
        }

        private func applySavedHeight(to window: NSWindow) {
            guard !window.inLiveResize else { return }
            let height = AppSettings.shared.settingsWindowHeight
            let current = window.contentRect(forFrameRect: window.frame).height
            guard abs(current - height) >= 1 else { return }
            window.setContentSize(NSSize(width: AppSettings.settingsWindowWidth, height: height))
        }

        private func persistHeight(of window: NSWindow) {
            let height = window.contentRect(forFrameRect: window.frame).height
            AppSettings.shared.saveSettingsWindowHeight(height)
        }
    }
}
