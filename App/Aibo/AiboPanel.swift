import AppKit

/// Borderless, non-activating desktop pet window.
final class AiboPanel: NSPanel {
    /// Onboarding URL / name fields need a key window; keep false otherwise.
    var allowsBecomingKey = false

    override var canBecomeKey: Bool { allowsBecomingKey }
    override var canBecomeMain: Bool { false }

    // Liquid Glass consults AppKit's window appearance, not SwiftUI's
    // `appearsActive`. A non-key panel otherwise loses the regular refraction
    // and gives clear glass a heavy blur. Keep presentation active without
    // changing key-window eligibility or keyboard focus.
    // This undocumented AppKit selector needs revalidation on macOS updates;
    // if AppKit stops consulting it, the system's inactive appearance returns.
    @objc(_hasActiveAppearance)
    private func usesActiveGlassAppearance() -> Bool { true }

    /// SwiftUI (text selection, `Button`, context menu) still calls `makeKey`
    /// on a `.nonactivatingPanel`. Refuse it unless onboarding needs a field.
    override func makeKey() {
        guard allowsBecomingKey else { return }
        super.makeKey()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        if allowsBecomingKey {
            super.makeKeyAndOrderFront(sender)
        } else {
            orderFront(sender)
        }
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = true
        // Drag only via PassThroughHostingView on opaque pet pixels.
        // Background-move would also grab music-note padding / empty layout.
        isMovableByWindowBackground = false
    }

    /// NSHostingView has repeatedly driven width/height to 0 via content-size extrema;
    /// refuse degenerate frames so constraint recursion can't take hold.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var safe = frameRect
        safe.size.width = max(safe.size.width, 1)
        safe.size.height = max(safe.size.height, 1)
        super.setFrame(safe, display: flag)
    }

    override func setContentSize(_ size: NSSize) {
        super.setContentSize(
            NSSize(width: max(size.width, 1), height: max(size.height, 1))
        )
    }
}

/// Window `contentView` wrapper so `NSHostingView` is *not* the content view.
///
/// When `NSHostingView` is the window content view, SwiftUI rewrites
/// `contentMinSize` / `contentMaxSize` from transient SwiftUI metrics (often during
/// Pow transitions), collapsing the panel to width 0 and crashing with an
/// Update Constraints loop.
final class AiboPanelRootView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        // Don't return `self` for empty areas — that would eat desktop clicks.
        for subview in subviews.reversed() {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local) {
                return hit
            }
        }
        return nil
    }
}
