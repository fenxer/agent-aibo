import AiboCore
import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case aibo
    case agentHook
    case webhook
    case extensions
    case tools
    case general
    case backup
    case about
    #if DEBUG
    case development
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aibo: String(localized: "Aibo")
        case .agentHook: String(localized: "Agent Hook")
        case .webhook: String(localized: "Webhook")
        case .extensions: String(localized: "Extensions")
        case .tools: String(localized: "Tools")
        case .general: String(localized: "General")
        case .backup: String(localized: "Backup")
        case .about: String(localized: "About")
        #if DEBUG
        case .development: String(localized: "Development")
        #endif
        }
    }

    enum Icon {
        case asset(String)
        case system(String)
    }

    var icon: Icon {
        switch self {
        case .aibo: .asset("HeartMenu")
        case .agentHook: .system("poweroutlet.type.b.fill")
        case .webhook: .system("globe")
        case .extensions: .system("square.text.square.fill")
        case .tools: .system("wrench.and.screwdriver.fill")
        case .general: .system("gearshape.fill")
        case .backup: .system("archivebox.fill")
        case .about: .system("info.circle.fill")
        #if DEBUG
        case .development: .system("hammer.fill")
        #endif
        }
    }

    var iconColor: Color {
        switch self {
        case .aibo: .red
        case .agentHook: .blue
        case .webhook: .blue
        case .extensions: .teal
        case .tools: .purple
        case .general: .indigo
        case .backup: .orange
        case .about: Color(nsColor: .systemGray)
        #if DEBUG
        case .development: .orange
        #endif
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .aibo: 18
        case .agentHook: 20
        case .webhook: 18
        case .extensions: 16
        case .tools: 15
        case .general: 18
        case .backup: 18
        case .about: 16
        #if DEBUG
        case .development: 16
        #endif
        }
    }

    init?(_ destination: SettingsNavigator.Pane) {
        switch destination {
        case .general: self = .general
        case .backup: self = .backup
        case .webhook: self = .webhook
        case .about: self = .about
        case .extensions: self = .extensions
        case .tools: self = .tools
        #if DEBUG
        case .development: self = .development
        #endif
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?
    @FocusState private var focused: Bool

    /// Gap between rows in one group. The old list stacked these flush.
    private static let rowSpacing: CGFloat = 4
    /// Gap between groups, in place of the collapsed section header.
    private static let sectionSpacing: CGFloat = 16

    private var sections: [[SettingsPane]] {
        var groups: [[SettingsPane]] = [
            [.aibo, .agentHook, .webhook],
            [.extensions],
            [.tools],
            [.general, .backup, .about],
        ]
        #if DEBUG
        groups.append([.development])
        #endif
        return groups
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                ForEach(sections, id: \.first) { group in
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(group) { pane in
                            row(pane)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(by: -1)
            case .down: moveSelection(by: 1)
            default: break
            }
        }
        .focusEffectDisabled()
        // Width must come after sidebar-toggle removal. The other way around,
        // AppKit resets the column to its default (~144) and ignores ideal.
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 220)
    }

    private func row(_ pane: SettingsPane) -> some View {
        SettingsSidebarRow(
            pane: pane,
            isSelected: selection == pane,
            select: {
                selection = pane
                focused = true
            }
        )
    }

    private func moveSelection(by step: Int) {
        let items = sections.flatMap { $0 }
        guard let current = selection, let index = items.firstIndex(of: current) else {
            selection = items.first
            return
        }
        let next = index + step
        guard items.indices.contains(next) else { return }
        selection = items[next]
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                SettingsSidebarIcon(pane: pane, isSelected: isSelected)
                    .accessibilityHidden(true)
                Text(pane.title)
                    .foregroundStyle(.primary)
                    .font(.system(size: 15))
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.tertiary).opacity(0.4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lub-dub, then a rest. The animator exists only while Aibo is selected,
/// so leaving the row — or closing Settings — leaves the heart still.
private struct HeartIconGlyph: View {
    var beating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if beating, !reduceMotion {
            glyph.keyframeAnimator(initialValue: 1.0, repeating: true) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.2, duration: 0.12)
                    CubicKeyframe(1.0, duration: 0.14)
                    CubicKeyframe(1.1, duration: 0.10)
                    CubicKeyframe(1.0, duration: 0.64)
                }
            }
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Image("HeartIconHeart")
            .resizable()
            .interpolation(.high)
            .frame(width: 12, height: 13)
    }
}

private struct SettingsSidebarIcon: View {
    let pane: SettingsPane
    var isSelected = false

    private let side: CGFloat = 28

    var body: some View {
        switch pane {
        case .aibo:
            aiboIcon
        case .agentHook:
            agentHookIcon
        default:
            symbolIcon
        }
    }

    /// Design frame is 28×28, origin at the top-left. The heart sits at (11, 11).
    private var aiboIcon: some View {
        Image("HeartIconLightBg")
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .overlay(alignment: .topLeading) {
                HeartIconGlyph(beating: isSelected)
                    .offset(x: 11, y: 11)
            }
    }

    /// Design frame is 28×28, origin at the top-left.
    /// Eyes are 4×8 at (7, 7) and (17, 7). The mouth is 10×5, centered, at y 18.
    private var agentHookIcon: some View {
        Image("AgentIconLightBg")
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .overlay(alignment: .topLeading) {
                AgentHookFace(tracking: isSelected)
            }
    }

    private var symbolIcon: some View {
        RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
            .fill(pane.iconColor)
            .frame(width: side, height: side)
            .overlay {
                switch pane.icon {
                case .asset(let name):
                    Image(name)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: pane.iconSize, height: pane.iconSize)
                case .system(let name):
                    Image(nsImage: Self.centeredSymbol(name, pointSize: pane.iconSize))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: pane.iconSize, height: pane.iconSize)
                }
            }
            .foregroundStyle(.white)
    }

    /// SF Symbols keep a text-baseline alignment rect, so `Image(systemName:)`
    /// sits low in a square. Bake a plain template image to center geometrically.
    private static func centeredSymbol(_ name: String, pointSize: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else {
            return NSImage()
        }
        let baked = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        baked.isTemplate = true
        return baked
    }
}

/// Eyes look toward the pointer and blink only while Agent Hook is selected.
/// The monitor and the blink task both go away when the row is not selected.
private struct AgentHookFace: View {
    var tracking: Bool

    fileprivate static let maxLook: CGFloat = 1.5
    fileprivate static let lookReach: CGFloat = 140

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var look: CGSize = .zero
    @State private var openness: CGFloat = 1

    private var followsPointer: Bool { tracking && !reduceMotion }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Offset does not affect layout, so without this the stack is only
            // as big as a glyph and gets centered in the icon.
            Color.clear
                .frame(width: 28, height: 28)
            eye.offset(eyePosition(homeX: 7, onLeft: true))
            eye.offset(eyePosition(homeX: 17, onLeft: false))
            sidebarGlyph("AgentIconMouth", width: 10, height: 5)
                .scaleEffect(x: 1, y: tracking ? 1 : -1, anchor: .center)
                .animation(.easeInOut(duration: 0.22), value: tracking)
                .offset(x: 9, y: 18)
        }
        .animation(.easeOut(duration: 0.12), value: look)
        .background {
            AgentGazeTracker(active: followsPointer) { look = $0 }
        }
        .task(id: followsPointer) {
            await blinkLoop()
        }
        .onChange(of: followsPointer) { _, follows in
            if !follows {
                look = .zero
                openness = 1
            }
        }
    }

    private var eye: some View {
        sidebarGlyph("AgentIconEye", width: 4, height: 8)
            .scaleEffect(x: 1, y: openness, anchor: .center)
    }

    /// The eye on the side being looked toward sits nearer the edge of the
    /// sphere, so it travels less than the far eye.
    private func eyePosition(homeX: CGFloat, onLeft: Bool) -> CGSize {
        let lookingRight = look.width >= 0
        let isNear = onLeft != lookingRight
        let travel = look.width * (isNear ? 0.45 : 1)
        return CGSize(width: homeX + travel, height: 7 + look.height)
    }

    private func blinkLoop() async {
        guard followsPointer else {
            openness = 1
            return
        }
        try? await Task.sleep(for: .milliseconds(Int.random(in: 500...1400)))
        while !Task.isCancelled {
            let times = Int.random(in: 1...2)
            for index in 0..<times {
                await blinkOnce()
                if index + 1 < times {
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 90...160)))
                }
            }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2200...5600)))
        }
    }

    private func blinkOnce() async {
        withAnimation(.easeIn(duration: 0.06)) { openness = 0.08 }
        try? await Task.sleep(for: .milliseconds(70))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.1)) { openness = 1 }
        try? await Task.sleep(for: .milliseconds(100))
    }
}

private func sidebarGlyph(_ name: String, width: CGFloat, height: CGFloat) -> some View {
    Image(name)
        .resizable()
        .interpolation(.high)
        .frame(width: width, height: height)
}

/// Reports a clamped look offset from this view's center toward the pointer.
/// Listens only while active, and only to events the settings window already receives.
private struct AgentGazeTracker: NSViewRepresentable {
    var active: Bool
    var onLook: (CGSize) -> Void

    func makeNSView(context: Context) -> AgentGazeView {
        let view = AgentGazeView()
        view.onLook = onLook
        return view
    }

    func updateNSView(_ view: AgentGazeView, context: Context) {
        view.onLook = onLook
        view.setActive(active)
    }

    static func dismantleNSView(_ view: AgentGazeView, coordinator: ()) {
        view.setActive(false)
    }
}

private final class AgentGazeView: NSView {
    var onLook: ((CGSize) -> Void)?

    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var trackedWindow: NSWindow?
    private var previousAcceptsMouseMoved = false
    private var wantsTracking = false
    private var pendingStart = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setActive(_ active: Bool) {
        wantsTracking = active
        if active {
            start()
        } else {
            stop()
            onLook?(.zero)
        }
    }

    private func start() {
        guard wantsTracking, monitor == nil else { return }
        guard let window else {
            guard !pendingStart else { return }
            pendingStart = true
            DispatchQueue.main.async { [weak self] in
                self?.pendingStart = false
                self?.start()
            }
            return
        }
        trackedWindow = window
        previousAcceptsMouseMoved = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.updateGaze(from: event)
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onLook?(.zero)
        }
    }

    private func stop() {
        pendingStart = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        trackedWindow?.acceptsMouseMovedEvents = previousAcceptsMouseMoved
        trackedWindow = nil
    }

    private func updateGaze(from event: NSEvent) {
        guard wantsTracking, event.window === trackedWindow, let center = screenCenter() else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let length = hypot(dx, dy)
        let maxLook = AgentHookFace.maxLook
        let amount = min(maxLook, length / AgentHookFace.lookReach * maxLook)
        let look: CGSize = length < 1
            ? .zero
            : CGSize(width: dx / length * amount, height: -dy / length * amount)
        onLook?(look)
    }

    private func screenCenter() -> CGPoint? {
        guard let window else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return window.convertPoint(toScreen: convert(center, to: nil))
    }
}

struct SettingsView: View {
    @State private var selection: SettingsPane?
    @Bindable private var navigator = SettingsNavigator.shared

    init() {
        _selection = State(initialValue: Self.initialPane())
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
        } detail: {
            // Detail panes own in-column sub-navigation and apply
            // `settingsDetailChrome` for the System Settings–style toolbar.
            detailRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Fill the window. Size is the window's, not this view's ideal size
        // (`SettingsWindowController` clears `sizingOptions`).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            applyPendingPane()
            navigator.rememberPane(id: selection?.rawValue)
        }
        .onChange(of: navigator.pendingPane) { _, newValue in
            guard newValue != nil else { return }
            applyPendingPane()
        }
        .onChange(of: selection) { _, newValue in
            navigator.rememberPane(id: newValue?.rawValue)
        }
    }

    /// Deep link wins over the pane from the last time Settings was open.
    private static func initialPane() -> SettingsPane {
        if let pending = SettingsNavigator.shared.pendingPane, let pane = SettingsPane(pending) {
            return pane
        }
        if let id = SettingsNavigator.shared.rememberedPaneID,
           let pane = SettingsPane(rawValue: id)
        {
            return pane
        }
        return .aibo
    }

    private func applyPendingPane() {
        guard let pending = navigator.consumePendingPane(),
              let pane = SettingsPane(pending)
        else { return }
        selection = pane
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection ?? .aibo {
        case .aibo:
            AiboSettingsPane()
        case .agentHook:
            AgentHookSettingsPane()
        case .general:
            GeneralSettingsPane()
        case .backup:
            BackupSettingsPane()
        case .webhook:
            WebhookSettingsPane()
        case .extensions:
            ExtensionSettingsPage()
        case .tools:
            ToolsSettingsPane()
        case .about:
            AboutSettingsPane()
        #if DEBUG
        case .development:
            DevelopmentSettingsPane()
        #endif
        }
    }
}

#Preview {
    SettingsView()
}
