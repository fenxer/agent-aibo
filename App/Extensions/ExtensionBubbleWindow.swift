import AiboCore
import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Set by the prompt window so multiline wells absorb extra window height.
    @Entry var extensionTextWellHeight: CGFloat? = nil
    /// Plugin icon's x from the window edge, after the traffic lights.
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

/// 52pt title band on the plugin window.
struct ExtensionWindowTitleBand: ViewModifier {
    @Environment(\.extensionWindowHeaderLeading) private var leading

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, -ExtensionBubbleMetrics.formPadding)
            .padding(.leading, leading)
            .padding(.trailing, ExtensionBubbleMetrics.windowHeaderTrailing)
            .frame(maxWidth: .infinity)
            .frame(height: ExtensionBubbleMetrics.windowHeaderBand, alignment: .center)
    }
}

/// 24×24 corner control that pins this specific plugin window above other apps.
struct ExtensionBubbleCornerButton: View {
    @Environment(ExtensionWindowInstance.self) private var windowInstance

    var body: some View {
        Button(action: windowInstance.togglePinned) {
            Image(systemName: windowInstance.isPinned ? "pin.fill" : "pin.slash.fill")
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

    private var help: String {
        if windowInstance.isPinned {
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

struct ExtensionBubbleWindowView: View {
    var instance: ExtensionWindowInstance
    private var center = ExtensionCenter.shared

    var body: some View {
        Group {
            if let presentation = center.presentation(for: instance.id) {
                ExtensionBubbleColumn(presentation: presentation, center: center)
            }
        }
        .environment(instance)
        .environment(\.extensionWindowHeaderLeading, headerLeading)
        .ignoresSafeArea(edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerShape(ExtensionWindowShape.shape)
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
            Button(action: { center.closeWindow(id: instance.id) }) {
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
        instance.trafficLightTrailing + ExtensionBubbleMetrics.windowControlGap
    }
}

/// Same outline as the glass. Content inside uses this so a nested corner can be concentric.
enum ExtensionWindowShape {
    static let shape = RoundedRectangle(
        cornerRadius: ExtensionBubbleMetrics.windowCornerRadius,
        style: .continuous
    )
}

/// Gray content platter in the plugin window.
/// Top corners stay a fixed radius; they sit under the title band, away from the window.
/// Bottom corners are concentric with the window, so they share its corner center.
struct ExtensionWindowContentFill: View {
    var topRadius: CGFloat
    var color: Color

    var body: some View {
        ConcentricRectangle(
            uniformTopCorners: .fixed(topRadius),
            uniformBottomCorners: .concentric(minimum: .fixed(topRadius))
        )
        .fill(color)
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

/// Per-window state so each open plugin window owns its own pin toggle,
/// traffic-light alignment, and frame tracking independently.
@MainActor
@Observable
final class ExtensionWindowInstance {
    let id: UUID
    /// `pin.fill` while this window stays above normal windows. Defaults to pinned.
    private(set) var isPinned = true
    /// Trailing edge of the zoom button after it has been seated, in the content view.
    private(set) var trafficLightTrailing: CGFloat = 80

    @ObservationIgnored var window: ExtensionBubbleWindow?
    @ObservationIgnored var delegate: ExtensionBubbleWindowDelegate?
    @ObservationIgnored var trafficLightObserver: NSObjectProtocol?
    @ObservationIgnored var isSeatingTrafficLights = false
    @ObservationIgnored var isPositioningProgrammatically = false
    @ObservationIgnored var hasSavedUserFrame = false
    @ObservationIgnored var activeFrameAutosaveName: String?

    init(id: UUID) {
        self.id = id
    }

    func togglePinned() {
        isPinned.toggle()
        applyLevel()
    }

    func applyLevel() {
        guard let window else { return }
        if isPinned {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window.level = .normal
            window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        }
    }

    func performProgrammaticFrameUpdate(_ body: () -> Void) {
        let previous = isPositioningProgrammatically
        isPositioningProgrammatically = true
        defer { isPositioningProgrammatically = previous }
        body()
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

    func noteUserFrameInteraction(_ window: NSWindow) {
        guard !isPositioningProgrammatically,
              window === self.window,
              window.isVisible,
              let key = activeFrameAutosaveName
        else { return }
        hasSavedUserFrame = true
        window.saveFrame(usingName: key)
    }

    func teardown() {
        if let observer = trafficLightObserver {
            NotificationCenter.default.removeObserver(observer)
            trafficLightObserver = nil
        }
        if let window {
            window.delegate = nil
            window.orderOut(nil)
            window.contentView = nil
        }
        delegate = nil
        window = nil
        activeFrameAutosaveName = nil
        hasSavedUserFrame = false
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
}

/// Manages all open plugin windows. Each extension ID remembers one frame;
/// additional simultaneous windows cascade by a small offset without overwriting it.
@MainActor
final class ExtensionBubbleWindowController {
    static let shared = ExtensionBubbleWindowController()

    private static let frameAutosavePrefix = "aibo.pluginBubbleWindow."
    private static let fileChoiceFrameAutosaveName = "aibo.pluginBubbleWindow.fileChoice"
    private static let cascadeOffset: CGFloat = 24
    private static let overlapThreshold: CGFloat = 16

    static func frameAutosaveName(forPluginID id: String) -> String {
        "\(frameAutosavePrefix)\(id)"
    }

    static func removeSavedFrame(forPluginID id: String) {
        NSWindow.removeFrame(usingName: frameAutosaveName(forPluginID: id))
    }

    private var instances: [UUID: ExtensionWindowInstance] = [:]

    private init() {}

    func present(windowID: UUID) {
        guard let presentation = ExtensionCenter.shared.presentation(for: windowID) else { return }
        let targetFrameName = frameAutosaveName(for: presentation)
        let instance = instances[windowID] ?? makeInstance(id: windowID)
        let window = ensureWindow(for: instance, presentation: presentation)
        let wasVisible = window.isVisible
        let switchedOwner = instance.activeFrameAutosaveName != targetFrameName
        instance.activeFrameAutosaveName = targetFrameName
        window.title = windowTitle(for: presentation)
        let siblingFrames = otherVisibleFrames(excluding: windowID)

        instance.performProgrammaticFrameUpdate {
            if !wasVisible || switchedOwner {
                let baseFrame: NSRect
                if window.setFrameUsingName(targetFrameName) {
                    instance.hasSavedUserFrame = true
                    baseFrame = clampToVisible(window.frame)
                } else {
                    instance.hasSavedUserFrame = false
                    baseFrame = initialFrame(for: presentation)
                }
                let finalFrame = cascadedFrame(from: baseFrame, avoiding: siblingFrames)
                if !framesMatch(window.frame, finalFrame) {
                    window.setFrame(finalFrame, display: false)
                }
            } else if !instance.hasSavedUserFrame {
                growWindowToFitIfNeeded(window, presentation: presentation)
            } else {
                let clamped = clampToVisible(window.frame)
                if !framesMatch(window.frame, clamped) {
                    window.setFrame(clamped, display: false)
                }
            }
            instance.applyLevel()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        instance.seatTrafficLights()
    }

    /// Expands an unpositioned window downward when the active phase grows taller
    /// (for example moving from missing-dependency to editing, or editing to a longer result).
    func syncNaturalHeightIfUnpositioned(windowID: UUID) {
        guard let instance = instances[windowID],
              let window = instance.window,
              window.isVisible,
              !instance.hasSavedUserFrame,
              let presentation = ExtensionCenter.shared.presentation(for: windowID)
        else { return }
        instance.performProgrammaticFrameUpdate {
            growWindowToFitIfNeeded(window, presentation: presentation)
        }
        instance.seatTrafficLights()
    }

    /// Close and release one plugin window. Callers clear presentation state first.
    func dismiss(windowID: UUID) {
        guard let instance = instances.removeValue(forKey: windowID) else { return }
        instance.teardown()
    }

    private func makeInstance(id: UUID) -> ExtensionWindowInstance {
        let instance = ExtensionWindowInstance(id: id)
        instances[id] = instance
        return instance
    }

    private func frameAutosaveName(for presentation: ExtensionWindowPresentation) -> String {
        switch presentation.content {
        case .session(let session):
            Self.frameAutosaveName(forPluginID: session.pluginID)
        case .fileChoice:
            Self.fileChoiceFrameAutosaveName
        }
    }

    private func windowTitle(for presentation: ExtensionWindowPresentation) -> String {
        switch presentation.content {
        case .session(let session):
            session.pluginName
        case .fileChoice:
            String(localized: "Choose an Extension")
        }
    }

    private func ensureWindow(
        for instance: ExtensionWindowInstance,
        presentation: ExtensionWindowPresentation
    ) -> ExtensionBubbleWindow {
        if let window = instance.window { return window }
        let window = ExtensionBubbleWindow(contentRect: initialFrame(for: presentation))
        let delegate = ExtensionBubbleWindowDelegate(instance: instance)
        instance.delegate = delegate
        window.delegate = delegate
        installContent(in: window, instance: instance)
        let minimum = ExtensionBubbleMetrics.windowMinimumSize
        window.contentMinSize = minimum
        window.minSize = minimum
        instance.window = window
        instance.applyLevel()
        watchTrafficLights(on: window, instance: instance)
        return window
    }

    /// NSHostingView must not be the content view. As contentView it rewrites
    /// contentMinSize / contentMaxSize from transient SwiftUI metrics and can
    /// collapse the window the same way it collapsed the pet panel.
    private func installContent(in window: ExtensionBubbleWindow, instance: ExtensionWindowInstance) {
        let root = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        let hosting = ExtensionBubbleHostingView(rootView: ExtensionBubbleWindowView(instance: instance))
        hosting.sizingOptions = []
        hosting.frame = root.bounds
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)
        window.contentView = root
    }

    private func watchTrafficLights(on window: NSWindow, instance: ExtensionWindowInstance) {
        guard instance.trafficLightObserver == nil,
              let close = window.standardWindowButton(.closeButton)
        else { return }
        close.postsFrameChangedNotifications = true
        instance.trafficLightObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: close,
            queue: .main
        ) { [weak instance] _ in
            MainActor.assumeIsolated {
                instance?.seatTrafficLights()
            }
        }
    }

    private func otherVisibleFrames(excluding windowID: UUID) -> [NSRect] {
        instances.values.compactMap { other in
            guard other.id != windowID, let window = other.window, window.isVisible else { return nil }
            return window.frame
        }
    }

    /// Offsets a newly opened window if another open plugin window sits at the same top-left spot.
    private func cascadedFrame(from baseFrame: NSRect, avoiding occupied: [NSRect]) -> NSRect {
        guard !occupied.isEmpty else { return baseFrame }
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(baseFrame) }
            ?? AiboPanelController.shared.petScreen()
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let stepX: CGFloat = baseFrame.maxX + Self.cascadeOffset <= visible.maxX
            ? Self.cascadeOffset
            : -Self.cascadeOffset
        let stepY: CGFloat = baseFrame.minY - Self.cascadeOffset >= visible.minY
            ? -Self.cascadeOffset
            : Self.cascadeOffset

        var candidate = baseFrame
        for _ in 0..<12 {
            let overlaps = occupied.contains { other in
                abs(other.minX - candidate.minX) < Self.overlapThreshold
                    && abs(other.maxY - candidate.maxY) < Self.overlapThreshold
            }
            guard overlaps else { return candidate }
            var shifted = candidate
            shifted.origin.x += stepX
            shifted.origin.y += stepY
            let next = clampToVisible(shifted)
            if framesMatch(next, candidate) {
                break
            }
            candidate = next
        }
        return candidate
    }

    private func growWindowToFitIfNeeded(
        _ window: NSWindow,
        presentation: ExtensionWindowPresentation
    ) {
        let minimum = ExtensionBubbleMetrics.windowMinimumSize
        let neededHeight = max(naturalWindowHeight(for: presentation), minimum.height)
        guard neededHeight > window.frame.height + 1 else {
            let clamped = clampToVisible(window.frame)
            if !framesMatch(window.frame, clamped) {
                window.setFrame(clamped, display: false)
            }
            return
        }
        var grown = window.frame
        grown.origin.y = window.frame.maxY - neededHeight
        grown.size.height = neededHeight
        let clamped = clampToVisible(grown)
        if !framesMatch(window.frame, clamped) {
            window.setFrame(clamped, display: false)
        }
    }

    private func naturalWindowHeight(for presentation: ExtensionWindowPresentation) -> CGFloat {
        let minimum = ExtensionBubbleMetrics.windowMinimumSize.height
        switch presentation.content {
        case .fileChoice(let choice):
            return max(
                minimum,
                ExtensionBubbleMetrics.fileChoiceCardHeight(count: choice.options.count) + 4
            )
        case .session(let session):
            switch session.phase {
            case .editing:
                return max(minimum, ExtensionBubbleMetrics.promptHeight(kinds: session.groupKinds) + 4)
            case .running(let message):
                return max(minimum, ExtensionBubbleMetrics.runningCardHeight(text: message) + 4)
            case .result(let summary, _):
                return max(minimum, ExtensionBubbleMetrics.statusHeight(text: summary) + 38)
            case .failed(let message, _):
                return max(minimum, ExtensionBubbleMetrics.statusHeight(text: message) + 38)
            case .notice(let summary, _):
                return max(minimum, ExtensionBubbleMetrics.statusHeight(text: summary) + 38)
            case .dependency(let issues):
                return max(minimum, ExtensionBubbleMetrics.dependencyCardHeight(count: issues.count) + 4)
            }
        }
    }

    /// Default placement before the user moves or resizes this extension's window: right beside the pet.
    private func initialFrame(for presentation: ExtensionWindowPresentation) -> NSRect {
        let minimum = ExtensionBubbleMetrics.windowMinimumSize
        let size = NSSize(
            width: minimum.width,
            height: max(naturalWindowHeight(for: presentation), minimum.height)
        )
        guard let pet = AiboPanelController.shared.petScreenRect() else {
            return clampToVisible(centered(size))
        }
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(pet) }
            ?? AiboPanelController.shared.petScreen()
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let record = AiboLibraryStore.shared.selectedRecord
        let gap = max(CGFloat(record.bubbleDistance), 12)
        let frame = besidePet(
            size: size,
            pet: pet,
            placement: record.bubblePlacement,
            gap: gap,
            visible: visible
        )
        return clampToVisible(frame)
    }

    private func besidePet(
        size: NSSize,
        pet: NSRect,
        placement: BubblePlacement,
        gap: CGFloat,
        visible: NSRect
    ) -> NSRect {
        let leftX = pet.minX - gap - size.width
        let rightX = pet.maxX + gap
        let aboveY = pet.maxY + gap
        let belowY = pet.minY - gap - size.height
        let centeredX = pet.midX - size.width / 2
        let centeredY = pet.midY - size.height / 2

        let origin: NSPoint
        switch placement {
        case .left:
            let fitsLeft = leftX >= visible.minX
            let fitsRight = rightX + size.width <= visible.maxX
            let x = (fitsLeft || !fitsRight) ? leftX : rightX
            origin = NSPoint(x: x, y: centeredY)
        case .right:
            let fitsRight = rightX + size.width <= visible.maxX
            let fitsLeft = leftX >= visible.minX
            let x = (fitsRight || !fitsLeft) ? rightX : leftX
            origin = NSPoint(x: x, y: centeredY)
        case .top:
            let fitsAbove = aboveY + size.height <= visible.maxY
            let fitsBelow = belowY >= visible.minY
            let y = (fitsAbove || !fitsBelow) ? aboveY : belowY
            origin = NSPoint(x: centeredX, y: y)
        case .bottom:
            let fitsBelow = belowY >= visible.minY
            let fitsAbove = aboveY + size.height <= visible.maxY
            let y = (fitsBelow || !fitsAbove) ? belowY : aboveY
            origin = NSPoint(x: centeredX, y: y)
        }
        return NSRect(origin: origin, size: size)
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

final class ExtensionBubbleWindowDelegate: NSObject, NSWindowDelegate {
    weak var instance: ExtensionWindowInstance?

    init(instance: ExtensionWindowInstance) {
        self.instance = instance
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            guard let id = instance?.id else { return }
            ExtensionCenter.shared.closeWindow(id: id)
        }
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            instance?.noteUserFrameInteraction(window)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            instance?.seatTrafficLights()
            instance?.noteUserFrameInteraction(window)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            instance?.noteUserFrameInteraction(window)
        }
    }
}
