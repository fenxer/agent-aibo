import AppKit
import Darwin
import SwiftUI

/// The Settings window. SwiftUI's `Settings` scene keeps its view tree after
/// the window hides (about 25 MB resident). This window is built on show and
/// dropped on close, so that tree goes with it.
///
/// Size belongs to the window: `NSHostingController.sizingOptions = []` stops
/// the hosting view from writing `contentMinSize` / `contentMaxSize` back
/// (an unconstrained `maxWidth` / `maxHeight` would otherwise lock or stretch
/// the frame). `.resizable` is in the style mask at creation. The last frame
/// is restored with `setFrameAutosaveName`; `isRestorable` stays false so
/// AppKit does not recreate the window — and the tree — at launch.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private static let frameAutosaveName: NSWindow.FrameAutosaveName = "AiboSettingsWindow"

    private var window: NSWindow?

    /// Raises the open window, or builds a new one. A closed window is not reused.
    func show() {
        if let window {
            raise(window)
            return
        }
        let window = makeWindow()
        self.window = window
        raise(window)
    }

    private func raise(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `activate` is asynchronous. Re-assert next turn, and never onto a
        // window that has since closed.
        let token = window
        Task { @MainActor in
            guard self.window === token else { return }
            token.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let defaultSize = NSSize(
            width: AppSettings.settingsWindowWidth,
            height: AppSettings.legacySettingsContentHeight()
        )
        let minimumSize = NSSize(
            width: AppSettings.settingsWindowMinWidth,
            height: AppSettings.settingsWindowMinHeight
        )
        // `defer: true` holds the backing store until the window is ordered on
        // screen, after the frame has been corrected below.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Settings")
        window.delegate = self
        window.isReleasedWhenClosed = false
        // State restoration would rebuild this window (and its SwiftUI tree) at launch.
        window.isRestorable = false
        window.isMovableByWindowBackground = false
        // Unified, before the hosting controller mounts. `.preference` centers
        // toolbar items; setting this afterwards gets overwritten by the bridge.
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.contentMinSize = minimumSize
        window.contentMaxSize = Self.maximumContentSize(for: window)

        let hosting = NSHostingController(rootView: SettingsView())
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = hosting
        // Assigning the controller resets the frame to the fitting size.
        // Restore the real size before ordering on screen, so the deferred
        // backing store is allocated once, at that size.
        window.setContentSize(defaultSize)
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden

        if !window.setFrameAutosaveName(Self.frameAutosaveName) {
            window.center()
        }
        window.contentMaxSize = Self.maximumContentSize(for: window)
        clampFrameToScreen(window)
        return window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.tearDownAfterClose()
        }
    }

    /// Live-resize floor. Autolayout ignores `contentMinSize`, and the hosting
    /// view deliberately has no size constraints.
    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MainActor.assumeIsolated {
            let minimum = NSSize(
                width: AppSettings.settingsWindowMinWidth,
                height: AppSettings.settingsWindowMinHeight
            )
            let minFrame = sender.frameRect(
                forContentRect: NSRect(origin: .zero, size: minimum)
            ).size
            let maxContent = Self.maximumContentSize(for: sender)
            let maxFrame = sender.frameRect(
                forContentRect: NSRect(origin: .zero, size: maxContent)
            ).size
            return NSSize(
                width: min(max(frameSize.width, minFrame.width), max(maxFrame.width, minFrame.width)),
                height: min(max(frameSize.height, minFrame.height), max(maxFrame.height, minFrame.height))
            )
        }
    }

    nonisolated func windowDidChangeScreen(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let window = notification.object as? NSWindow, window === self.window else { return }
            window.contentMaxSize = Self.maximumContentSize(for: window)
            clampFrameToScreen(window)
        }
    }

    private func tearDownAfterClose() {
        guard let window else { return }
        window.saveFrame(usingName: Self.frameAutosaveName)
        self.window = nil
        let closing = window
        Task { @MainActor in
            autoreleasepool {
                closing.contentViewController = nil
            }
            // Let SwiftUI and Core Animation drop the tree before asking
            // malloc to return the freed pages.
            await Task.yield()
            releaseSettingsSpriteCache()
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    /// Content size that fits the screen this window is on, so a restored or
    /// dragged frame cannot allocate a backing store larger than the display.
    private static func maximumContentSize(for window: NSWindow) -> NSSize {
        let screen = window.screen
            ?? NSScreen.screens.first { $0.frame.intersects(window.frame) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let content = window.contentRect(forFrameRect: visible).size
        return NSSize(
            width: max(content.width, AppSettings.settingsWindowMinWidth),
            height: max(content.height, AppSettings.settingsWindowMinHeight)
        )
    }

    private func clampFrameToScreen(_ window: NSWindow) {
        let maxContent = Self.maximumContentSize(for: window)
        let content = window.contentRect(forFrameRect: window.frame).size
        let clamped = NSSize(
            width: min(max(content.width, AppSettings.settingsWindowMinWidth), maxContent.width),
            height: min(max(content.height, AppSettings.settingsWindowMinHeight), maxContent.height)
        )
        guard abs(clamped.width - content.width) > 1 || abs(clamped.height - content.height) > 1 else {
            return
        }
        window.setContentSize(clamped)
    }

    /// Settings previews decode into `AiboSpriteCache` and otherwise stay
    /// until the library changes. Keep the desktop pet (and the pet a morph
    /// is still showing).
    private func releaseSettingsSpriteCache() {
        var keep: Set<String> = [AiboLibraryStore.shared.selectedID]
        if AiboSwitchSignal.shared.locksDesktopSize {
            keep.insert(AiboSwitchSignal.shared.fromID)
        }
        AiboSpriteCache.shared.releasePets(keeping: keep)
    }
}
