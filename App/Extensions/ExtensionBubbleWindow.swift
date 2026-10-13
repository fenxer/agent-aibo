import AiboCore
import AppKit
import SwiftUI

enum ExtensionBubbleChrome: Equatable {
    /// Card beside the pet.
    case anchored
    /// The same card in its own window.
    case window
}

extension EnvironmentValues {
    @Entry var extensionBubbleChrome: ExtensionBubbleChrome = .anchored
    /// Set by the detached prompt so multiline wells absorb extra window height.
    /// Nil keeps the bubble's fixed well.
    @Entry var extensionTextWellHeight: CGFloat? = nil
    /// Plugin icon's x from the window edge, after the traffic lights. Zero on the bubble.
    @Entry var extensionWindowHeaderLeading: CGFloat = 0
}

/// One trailing window control. A tint dyes the glass itself; the control has no fill behind it.
struct ExtensionWindowGlassButton: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(ExtensionBubbleMetrics.windowGlassPadding)
            .glassEffect(glass, in: Capsule())
    }

    private var glass: Glass {
        if let tint {
            .regular.tint(tint).interactive()
        } else {
            .regular.interactive()
        }
    }
}

/// 52pt band on the detached window. The bubble keeps the 24pt header.
struct ExtensionWindowTitleBand: ViewModifier {
    var enabled: Bool

    @Environment(\.extensionWindowHeaderLeading) private var leading

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, -ExtensionBubbleMetrics.formPadding)
                .padding(.leading, leading)
                .padding(.trailing, ExtensionBubbleMetrics.windowHeaderTrailing)
                .frame(maxWidth: .infinity)
                .frame(height: ExtensionBubbleMetrics.windowHeaderBand, alignment: .center)
        } else {
            content.frame(height: ExtensionBubbleMetrics.pluginHeaderHeight, alignment: .leading)
        }
    }
}

/// Header close control. The glyph stays 11pt; the hit target fills the 24pt header row.
struct ExtensionBubbleCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .frame(
                    width: ExtensionBubbleMetrics.cornerButtonSide,
                    height: ExtensionBubbleMetrics.cornerButtonSide,
                    alignment: .trailing
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
    }
}

/// 24×24 corner control. The bubble opens a window; the window pins itself above other apps.
struct ExtensionBubbleCornerButton: View {
    @Environment(\.extensionBubbleChrome) private var chrome

    private var window = ExtensionBubbleWindowController.shared

    var body: some View {
        Button(action: perform) {
            Image(systemName: symbolName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(
                    width: ExtensionBubbleMetrics.cornerButtonSide,
                    height: ExtensionBubbleMetrics.cornerButtonSide
                )
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private var symbolName: String {
        switch chrome {
        case .anchored:
            "arrow.up.right.square.fill"
        case .window:
            window.isPinned ? "pin.fill" : "pin.slash.fill"
        }
    }

    private var help: String {
        switch chrome {
        case .anchored:
            String(
                localized: "Open in Window",
                comment: "Button on a plugin bubble that opens the card in its own window."
            )
        case .window:
            if window.isPinned {
                String(
                    localized: "Stop Keeping on Top",
                    comment: "Button that lets the plugin window go behind other windows."
                )
            } else {
                String(
                    localized: "Keep on Top",
                    comment: "Button that keeps the plugin window above other windows."
                )
            }
        }
    }

    private func perform() {
        switch chrome {
        case .anchored:
            window.detach()
        case .window:
            window.togglePinned()
        }
    }
}

struct ExtensionBubbleWindowView: View {
    private var center = ExtensionCenter.shared
    private var windowModel = ExtensionBubbleWindowController.shared

    var body: some View {
        ExtensionBubbleColumn(placement: .bottom, showsArrow: false, center: center)
            .environment(\.extensionBubbleChrome, .window)
            .environment(\.extensionWindowHeaderLeading, headerLeading)
            .ignoresSafeArea(edges: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ExtensionWindowGlass.scrim)
            .background { ExtensionWindowGlassBackdrop() }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ExtensionBubbleMetrics.windowCornerRadius,
                    style: .continuous
                )
            )
            .ignoresSafeArea()
            .background {
                Button(action: { center.cancelSession() }) {
                    EmptyView()
                }
                .keyboardShortcut("w", modifiers: .command)
                .buttonStyle(.plain)
                .labelsHidden()
                .accessibilityHidden(true)
                .frame(width: 0, height: 0)
            }
    }

    /// Icon starts just after the zoom button. The title band cancels the card's own inset.
    private var headerLeading: CGFloat {
        windowModel.trafficLightTrailing + ExtensionBubbleMetrics.windowControlGap
    }
}

/// Note-window material: Liquid Glass, then a light or dark wash so the page stays readable.
private enum ExtensionWindowGlass {
    /// Dark appearance darkens the glass; light appearance lightens it.
    static let scrim = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.40)
        }
        return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
    })
}

private struct ExtensionWindowGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = ExtensionBubbleMetrics.windowCornerRadius
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = ExtensionBubbleMetrics.windowCornerRadius
    }
}

/// One plugin window for the current session. Frame comes from AppKit's autosave;
/// pin state is our own default because autosave does not store window level.
@MainActor
@Observable
final class ExtensionBubbleWindowController {
    static let shared = ExtensionBubbleWindowController()

    private(set) var isDetached = false
    /// `pin.fill` while the window stays above normal windows.
    private(set) var isPinned: Bool
    /// Trailing edge of the zoom button after it has been seated, in the content view.
    private(set) var trafficLightTrailing: CGFloat = 80

    private var isSeatingTrafficLights = false
    private var trafficLightObserver: NSObjectProtocol?

    private var window: ExtensionBubbleWindow?
    private let windowDelegate = ExtensionBubbleWindowDelegate()

    private enum Keys {
        static let pinned = "extensionBubbleWindow.pinned"
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.pinned) == nil {
            // The card was floating with the pet. Stay above other apps until the user unpins.
            isPinned = true
        } else {
            isPinned = defaults.bool(forKey: Keys.pinned)
        }
    }

    func detach() {
        guard ExtensionCenter.shared.session != nil else { return }
        if isDetached, window?.isVisible == true {
            present()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDetached = true
        }
        present()
        // No poof on the pet: drop the card slot on the next turn so hit rects
        // match the layout without the plugin.
        AiboPanelController.shared.notePluginWindowDetached()
        AiboPanelController.shared.updateOnboardingKeyWindow()
    }

    func togglePinned() {
        isPinned.toggle()
        UserDefaults.standard.set(isPinned, forKey: Keys.pinned)
        if let window {
            applyLevel(to: window)
        }
    }

    /// Hide without ending the session. `cancelSession` clears the session first.
    func dismiss() {
        isDetached = false
        window?.orderOut(nil)
    }

    private func present() {
        let window = ensureWindow()
        window.title = ExtensionCenter.shared.session?.pluginName ?? ""
        let clamped = clampToVisible(window.frame)
        if !framesMatch(window.frame, clamped) {
            window.setFrame(clamped, display: false)
        }
        applyLevel(to: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        seatTrafficLights()
    }

    private func ensureWindow() -> ExtensionBubbleWindow {
        if let window { return window }
        let window = ExtensionBubbleWindow(contentRect: initialFrame())
        window.delegate = windowDelegate
        installContent(in: window)
        let minimum = ExtensionBubbleMetrics.windowMinimumSize
        window.contentMinSize = minimum
        window.minSize = minimum
        // Restores the last origin and size when this name was saved before.
        if window.setFrameAutosaveName("aibo.pluginBubbleWindow") {
            window.setFrame(clampToVisible(window.frame), display: false)
        }
        applyLevel(to: window)
        watchTrafficLights(on: window)
        self.window = window
        return window
    }

    /// NSHostingView must not be the content view. As contentView it rewrites
    /// contentMinSize / contentMaxSize from transient SwiftUI metrics and can
    /// collapse the window the same way it collapsed the pet panel.
    private func installContent(in window: ExtensionBubbleWindow) {
        let root = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        let hosting = ExtensionBubbleHostingView(rootView: ExtensionBubbleWindowView())
        hosting.sizingOptions = []
        hosting.frame = root.bounds
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)
        window.contentView = root
    }

    /// AppKit's titlebar is shorter than the drawn band, so the lights are pushed to its
    /// bottom edge. That lands them on the band's vertical center. Idempotent: AppKit
    /// puts them back on resize and after the title changes.
    func seatTrafficLights() {
        guard !isSeatingTrafficLights, let window else { return }
        isSeatingTrafficLights = true
        defer { isSeatingTrafficLights = false }
        window.layoutIfNeeded()
        let buttons = [
            NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton,
        ].compactMap(window.standardWindowButton)
        guard let leading = buttons.first, let band = leading.superview?.bounds.height else { return }
        let size = leading.frame.height
        let y = max(
            0,
            band - size - (ExtensionBubbleMetrics.windowHeaderBand - size) / 2
        )
        let shift = ExtensionBubbleMetrics.windowTrafficLightInset - leading.frame.minX
        if abs(shift) > 0.5 || abs(leading.frame.origin.y - y) > 0.5 {
            for button in buttons {
                button.frame.origin.x += shift
                button.frame.origin.y = y
            }
        }
        syncTrafficLightInsets()
    }

    private func watchTrafficLights(on window: NSWindow) {
        guard trafficLightObserver == nil, let close = window.standardWindowButton(.closeButton) else {
            return
        }
        close.postsFrameChangedNotifications = true
        trafficLightObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: close,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ExtensionBubbleWindowController.shared.seatTrafficLights()
            }
        }
    }

    private func syncTrafficLightInsets() {
        guard let window, let content = window.contentView,
              let zoom = window.standardWindowButton(.zoomButton) else { return }
        let zoomBox = content.convert(zoom.bounds, from: zoom)
        guard content.bounds.height > 1, zoomBox.maxX > 1 else { return }
        if abs(zoomBox.maxX - trafficLightTrailing) > 0.5 {
            trafficLightTrailing = zoomBox.maxX
        }
    }

    private func applyLevel(to window: NSWindow) {
        if isPinned {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window.level = .normal
            window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        }
    }

    /// First open matches the bubble. Later opens keep the autosaved frame.
    private func initialFrame() -> NSRect {
        let minimum = ExtensionBubbleMetrics.windowMinimumSize
        let natural = ExtensionCenter.shared.session?.layoutHeights.first ?? minimum.height
        let size = NSSize(width: minimum.width, height: max(natural, minimum.height))
        if let bubble = AiboPanelController.shared.extensionCardScreenRect() {
            let frame = NSRect(
                x: bubble.minX,
                y: bubble.maxY - size.height,
                width: size.width,
                height: size.height
            )
            return clampToVisible(frame)
        }
        return clampToVisible(centered(size))
    }

    private func centered(_ size: NSSize) -> NSRect {
        let visible = AiboPanelController.shared.petScreen()?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clampToVisible(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let screen = screens.first { $0.visibleFrame.intersects(frame) }
            ?? AiboPanelController.shared.petScreen()
            ?? screens.first
        guard let screen else { return frame }
        let visible = screen.visibleFrame
        let minimum = ExtensionBubbleMetrics.windowMinimumSize
        var result = frame
        result.size.width = min(max(result.width, minimum.width), visible.width)
        result.size.height = min(max(result.height, minimum.height), visible.height)
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        return result
    }

    private func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }
}

/// A normal window, not a panel: panels hide when the app deactivates, and this
/// one has to drop to `.normal` when it is not pinned. The titlebar is transparent
/// and full-size so the traffic lights sit on the plugin header row. Edges still resize.
final class ExtensionBubbleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        tabbingMode = .disallowed
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var safe = frameRect
        safe.size.width = max(safe.size.width, 1)
        safe.size.height = max(safe.size.height, 1)
        super.setFrame(safe, display: flag)
    }

    override func setContentSize(_ size: NSSize) {
        super.setContentSize(NSSize(width: max(size.width, 1), height: max(size.height, 1)))
    }
}

/// Empty areas drag the window. Controls and text fields are subviews, so they still receive the click.
/// The view stays clear so the glass behind it samples the desktop, not an opaque hosting fill.
private final class ExtensionBubbleHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class ExtensionBubbleWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            ExtensionCenter.shared.cancelSession()
        }
        return false
    }

    func windowDidResize(_ notification: Notification) {
        MainActor.assumeIsolated {
            ExtensionBubbleWindowController.shared.seatTrafficLights()
        }
    }
}
