import AppKit
import SwiftUI

/// SwiftUI creates the `Settings` window without `.resizable`, and scene-level
/// `windowResizability` does not add it. Inserting it once is not enough either:
/// SwiftUI re-syncs the window's sizing config shortly after and strips the flag
/// again. So re-assert it on `didUpdate` (event-driven, no timer).
///
/// Equal min/max content width keeps the width fixed — only the height resizes.
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
        private var updateObserver: NSObjectProtocol?
        private var resizeObserver: NSObjectProtocol?

        func attach(to window: NSWindow?) {
            guard let window else { return }
            enforceConstraints(on: window)

            guard window !== observedWindow else { return }
            detach()
            observedWindow = window
            applySavedHeight(to: window)
            // First attach / new window instance — promote + key (menu / SettingsLink).
            SettingsNavigator.shared.handleSettingsWindowAppeared(window)

            updateObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.enforceConstraints(on: window)
                }
            }

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
            if let updateObserver {
                NotificationCenter.default.removeObserver(updateObserver)
                self.updateObserver = nil
            }
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            observedWindow = nil
        }

        /// Cheap no-op when nothing drifted; runs on every window update.
        private func enforceConstraints(on window: NSWindow) {
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }

            let width = AppSettings.settingsWindowWidth
            let minSize = NSSize(width: width, height: AppSettings.settingsWindowMinHeight)
            let maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            if window.contentMinSize != minSize {
                window.contentMinSize = minSize
            }
            if window.contentMaxSize != maxSize {
                window.contentMaxSize = maxSize
            }
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
