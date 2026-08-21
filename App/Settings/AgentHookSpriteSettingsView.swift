import AiboCore
import AppKit
import SwiftUI

/// Per-agent hook install, bubble style, and Petdex sprite mapping.
struct AgentHookSpriteSettingsView: View {
    let agent: AgentKind
    var onBack: () -> Void

    @State private var hoveredHook: String?
    @State private var hoveredSprite: PetdexSpriteState?
    @State private var isAiboPreviewStuck = false

    var body: some View {
        ZStack(alignment: .top) {
            Form {
                AgentHookAdvancedHeaderSection(agent: agent)

                AgentHookBubbleSection(agent: agent)

                AgentHookAiboActionsPreviewSection(
                    agent: agent,
                    hoveredHook: hoveredHook,
                    hoveredSprite: hoveredSprite,
                    isStuck: $isAiboPreviewStuck
                )

                AgentHookAiboActionsSection(
                    agent: agent,
                    hoveredHook: $hoveredHook,
                    hoveredSprite: $hoveredSprite
                )
            }
            .formStyle(.grouped)

            if isAiboPreviewStuck {
                AgentHookSpritePreviewHost(
                    agent: agent,
                    hoveredHook: hoveredHook,
                    hoveredSprite: hoveredSprite
                )
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Divider()
                }
                .transition(
                    .opacity
                        .combined(with: .offset(y: -12))
                        .combined(with: .scale(scale: 0.8, anchor: .top))
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isAiboPreviewStuck)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: StatusCopy.displayName(agent), canGoBack: true, onBack: onBack)
    }
}

private struct AgentHookAdvancedHeaderSection: View {
    let agent: AgentKind

    @State private var runtime = AiboRuntime.shared

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                AgentHookAdvancedIcon(assetName: agent.settingsIconAssetName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(StatusCopy.displayName(agent))
                        .font(.headline)
                    Text(String(localized: "Hook and style settings"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle(
                    String(localized: "Installed"),
                    isOn: installedBinding
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
        } footer: {
            Text(agentFooter)
        }
    }

    private var installedBinding: Binding<Bool> {
        Binding(
            get: { runtime.isHookInstalled(for: agent) },
            set: { enabled in
                if enabled {
                    runtime.installHooks(for: agent)
                } else {
                    runtime.uninstallHooks(for: agent)
                }
            }
        )
    }

    private var agentFooter: String {
        switch agent {
        case .cursor:
            String(localized: "Cursor does not support approval or prompt-waiting hook events yet.")
        case .codex:
            String(localized: "Codex PermissionRequest starts as “is reviewing”, then escalates to “got stuck?” after a few seconds.")
        case .deepseek:
            String(localized: "Observe-only Cordis plugin. Writes a marked block into ~/.dsh/cordis.patch.yml (or $DSH_HOME). Restart `dsh` after install. Don’t also `dsh plugin add` the same plugin. Clicking the bubble does not switch apps yet.")
        }
    }
}

private struct AgentHookAdvancedIcon: View {
    var assetName: String

    @Environment(\.colorScheme) private var colorScheme

    private let side: CGFloat = 28

    var body: some View {
        let isDark = colorScheme == .dark
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isDark ? Color.white : Color.black)
            .frame(width: side, height: side)
            .overlay {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .foregroundStyle(isDark ? Color.black : Color.white)
            }
            .accessibilityHidden(true)
    }
}

private struct AgentHookBubbleSection: View {
    let agent: AgentKind

    @Bindable private var settings = AppSettings.shared
    @State private var previewKind: AgentHookBubblePreviewKind = .agent

    var body: some View {
        Group {
            Section {
                AgentHookBubblePreview(
                    agent: agent,
                    previewKind: $previewKind,
                    glassStyle: settings.agentBubbleGlassStyle(for: agent),
                    glassTint: settings.agentBubbleGlassTint(for: agent)
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text(String(localized: "Bubble"))
            }

            Section {
                Picker(
                    String(localized: "Background Material"),
                    selection: glassStyleBinding
                ) {
                    ForEach(BubbleGlassStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                LabeledContent(String(localized: "Background Tint Color")) {
                    HStack(spacing: 8) {
                        if settings.agentBubbleGlassTint(for: agent) != nil {
                            ColorPicker(
                                String(localized: "Background Tint Color"),
                                selection: glassTintColorBinding,
                                supportsOpacity: true
                            )
                            .labelsHidden()
                        }

                        Toggle(
                            String(localized: "Background Tint Color"),
                            isOn: glassTintEnabledBinding
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                LabeledContent(String(localized: "Capsule Color")) {
                    HStack(spacing: 8) {
                        if settings.agentCapsuleColor(for: agent) != nil {
                            Button {
                                settings.setAgentCapsuleColor(nil, for: agent)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(String(localized: "Reset Capsule Color"))
                            .accessibilityLabel(String(localized: "Reset Capsule Color"))
                        }

                        ColorPicker(
                            String(localized: "Capsule Color"),
                            selection: capsuleColorBinding,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }
            }
            .labeledContentStyle(AgentHookCenteredLabeledContentStyle())
        }
    }

    private var glassStyleBinding: Binding<BubbleGlassStyle> {
        Binding(
            get: { settings.agentBubbleGlassStyle(for: agent) },
            set: { settings.setAgentBubbleGlassStyle($0, for: agent) }
        )
    }

    private var glassTintEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.agentBubbleGlassTint(for: agent) != nil },
            set: { enabled in
                if enabled {
                    settings.setAgentBubbleGlassTint(
                        settings.agentBubbleGlassTint(for: agent) ?? .accentColor,
                        for: agent
                    )
                } else {
                    settings.setAgentBubbleGlassTint(nil, for: agent)
                }
            }
        )
    }

    private var glassTintColorBinding: Binding<Color> {
        Binding(
            get: { settings.agentBubbleGlassTint(for: agent) ?? .accentColor },
            set: { settings.setAgentBubbleGlassTint($0, for: agent) }
        )
    }

    private var capsuleColorBinding: Binding<Color> {
        Binding(
            get: { settings.agentCapsuleColor(for: agent) ?? .black },
            set: { settings.setAgentCapsuleColor($0, for: agent) }
        )
    }
}

private enum AgentHookBubblePreviewKind: Hashable {
    case agent
    case subagent
}

private struct AgentHookBubblePreview: View {
    let agent: AgentKind
    @Binding var previewKind: AgentHookBubblePreviewKind
    var glassStyle: BubbleGlassStyle
    var glassTint: Color?

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                Image("WallpaperBg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width + 20, height: geo.size.height + 20)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .accessibilityHidden(true)
            }

            StatusBubble(
                item: previewItem,
                placement: .top,
                showsArrow: false,
                glassStyle: glassStyle,
                glassTint: glassTint
            )
            .padding(.top, 40)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .overlay(alignment: .topLeading) {
            Text(String(localized: "PREVIEW"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
        .overlay(alignment: .bottom) {
            Picker(selection: $previewKind) {
                Text(String(localized: "Default")).tag(AgentHookBubblePreviewKind.agent)
                Text(String(localized: "Subagent")).tag(AgentHookBubblePreviewKind.subagent)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .modifier(AgentHookPreviewPickerStyle())
            .frame(width: 180)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
    }

    private var previewItem: StatusBubbleItem {
        let isSubagent = previewKind == .subagent
        return StatusBubbleItem(
            id: "agent-hook-preview-\(agent.rawValue)",
            text: StatusCopy.statusPhrase(for: .thinking) ?? "is thinking",
            lastEventAt: .now,
            animatesEllipsis: true,
            agentName: isSubagent ? "Subagent" : StatusCopy.displayName(agent),
            iconAssetName: agent.settingsIconAssetName,
            projectName: "PROJECT",
            modelName: "model-name",
            isSubagent: isSubagent,
            agent: agent
        )
    }
}

/// `.tabs` is macOS 27+; 26 keeps the segmented control.
private struct AgentHookPreviewPickerStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            content
                .pickerStyle(.tabs)
                .buttonBorderShape(.capsule)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

private struct AgentHookAiboActionsPreviewSection: View {
    let agent: AgentKind
    var hoveredHook: String?
    var hoveredSprite: PetdexSpriteState?
    @Binding var isStuck: Bool

    var body: some View {
        Section {
            AgentHookSpritePreviewHost(
                agent: agent,
                hoveredHook: hoveredHook,
                hoveredSprite: hoveredSprite
            )
            .opacity(isStuck ? 0 : 1)
            .background {
                AgentHookViewportTopExitMonitor { exited in
                    if exited != isStuck {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isStuck = exited
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text(String(localized: "Aibo Actions"))
        }
    }
}

private struct AgentHookAiboActionsSection: View {
    let agent: AgentKind
    @Binding var hoveredHook: String?
    @Binding var hoveredSprite: PetdexSpriteState?

    @Bindable private var hookSprites = HookSpriteSettings.shared

    private var hooks: [String] {
        HookSpriteMapping.configurableHooks(for: agent)
    }

    var body: some View {
        Section {
            ForEach(hooks, id: \.self) { hook in
                AgentHookActionRow(
                    agent: agent,
                    hook: hook,
                    hoveredHook: $hoveredHook,
                    hoveredSprite: $hoveredSprite
                )
            }

            if hookSprites.hasCustomOverrides(for: agent) {
                Button(String(localized: "Reset to Defaults"), role: .destructive) {
                    hookSprites.resetAll(for: agent)
                }
            }
        } footer: {
            Text(String(localized: "Choose which Petdex animation plays when each hook fires. Applies when a Petdex aibo is selected. Hover a row to preview it."))
        }
        .labeledContentStyle(AgentHookCenteredLabeledContentStyle())
    }
}

private struct AgentHookActionRow: View {
    let agent: AgentKind
    let hook: String
    @Binding var hoveredHook: String?
    @Binding var hoveredSprite: PetdexSpriteState?

    @Bindable private var hookSprites = HookSpriteSettings.shared
    @State private var isMenuOpen = false

    private var isHovered: Bool {
        hoveredHook == hook
    }

    var body: some View {
        LabeledContent {
            AgentHookSpritePopUp(
                selection: spriteBinding,
                onHighlight: { hoveredSprite = $0 },
                onOpen: {
                    isMenuOpen = true
                    hoveredHook = hook
                },
                onClose: {
                    isMenuOpen = false
                    hoveredSprite = nil
                }
            )
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(hook)
                if let description = StatusCopy.hookSettingDescription(
                    agent: agent,
                    hookEventName: hook
                ) {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.primary.opacity(isHovered ? 0.08 : 0)
        }
        .contentShape(Rectangle())
        .padding(-10)
        .overlay {
            AgentHookRowHoverProbe { hovering in
                if hovering {
                    hoveredHook = hook
                } else if !isMenuOpen, hoveredHook == hook {
                    hoveredHook = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private var spriteBinding: Binding<PetdexSpriteState> {
        Binding(
            get: { hookSprites.sprite(for: agent, hookEventName: hook) },
            set: { hookSprites.setSprite($0, agent: agent, hookEventName: hook) }
        )
    }
}

private struct AgentHookSpritePreviewHost: View {
    let agent: AgentKind
    var hoveredHook: String?
    var hoveredSprite: PetdexSpriteState?

    @Bindable private var hookSprites = HookSpriteSettings.shared
    private var library = AiboLibraryStore.shared

    private var hooks: [String] {
        HookSpriteMapping.configurableHooks(for: agent)
    }

    private var previewHook: String? {
        hoveredHook ?? hooks.first
    }

    private var previewState: PetdexSpriteState {
        if let hoveredSprite { return hoveredSprite }
        guard let previewHook else { return .idle }
        return hookSprites.sprite(for: agent, hookEventName: previewHook)
    }

    private var previewRecord: AiboLibraryRecord? {
        let selected = library.selectedRecord
        if AiboSpritePack.directory(for: selected) != nil { return selected }
        return library.records.first { AiboSpritePack.directory(for: $0) != nil }
    }

    var body: some View {
        AgentHookSpritePreviewBand(
            record: previewRecord,
            state: previewState,
            localizedName: localizedSpriteName(previewState)
        )
    }
}

private struct AgentHookSpritePreviewBand: View {
    var record: AiboLibraryRecord?
    var state: PetdexSpriteState
    var localizedName: String

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let record {
                    PetdexSpritePreview(record: record, state: state, size: 96)
                        .accessibilityLabel(localizedName)
                } else {
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Petdex Aibo"),
                            systemImage: "pawprint"
                        )
                    } description: {
                        Text(String(localized: "Install or select a Petdex aibo in Aibo to preview animations."))
                    }
                    .frame(minHeight: 120)
                }
            }

            Text(localizedName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private func localizedSpriteName(_ state: PetdexSpriteState) -> String {
    switch state {
    case .idle: String(localized: "Idle")
    case .runningRight: String(localized: "Run Right")
    case .runningLeft: String(localized: "Run Left")
    case .waving: String(localized: "Waving")
    case .jumping: String(localized: "Jumping")
    case .failed: String(localized: "Failed")
    case .waiting: String(localized: "Waiting")
    case .running: String(localized: "Running")
    case .review: String(localized: "Review")
    }
}

/// Loops one Petdex atlas row for settings preview (always animates, including Idle).
private struct PetdexSpritePreview: View {
    var record: AiboLibraryRecord
    var state: PetdexSpriteState
    var size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let index = frameIndex(at: timeline.date)
            if let image = AiboSpriteCache.shared.frame(for: record, state: state, frameIndex: index) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .id("\(record.id)-\(state.rawValue)")
    }

    private var frameInterval: TimeInterval {
        let ms = max(state.durationMilliseconds / max(state.frameCount, 1), 80)
        return Double(ms) / 1000.0
    }

    private func frameIndex(at date: Date) -> Int {
        guard frameInterval > 0 else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / frameInterval)
    }
}

/// Centers the trailing control against a title + subtitle label.
private struct AgentHookCenteredLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}

/// Form `listRowBackground` views are often not in the live hit-test tree.
/// Probe lives in the row content and hit-tests the enclosing table row.
private struct AgentHookRowHoverProbe: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> AgentHookRowHoverTarget {
        let view = AgentHookRowHoverTarget()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: AgentHookRowHoverTarget, context: Context) {
        view.onHover = onHover
    }

    static func dismantleNSView(_ view: AgentHookRowHoverTarget, coordinator: ()) {
        view.teardown()
    }
}

@MainActor
private final class AgentHookRowHoverRouter {
    static let shared = AgentHookRowHoverRouter()

    private var monitor: Any?
    private let targets = NSHashTable<AgentHookRowHoverTarget>.weakObjects()
    private var previousAcceptsMouseMoved: [ObjectIdentifier: Bool] = [:]

    func register(_ target: AgentHookRowHoverTarget) {
        targets.add(target)
        if let window = target.window {
            let id = ObjectIdentifier(window)
            if previousAcceptsMouseMoved[id] == nil {
                previousAcceptsMouseMoved[id] = window.acceptsMouseMovedEvents
                window.acceptsMouseMovedEvents = true
            }
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dispatch(event)
            }
            return event
        }
    }

    func unregister(_ target: AgentHookRowHoverTarget) {
        let window = target.window
        targets.remove(target)
        guard targets.count == 0 else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let window {
            let id = ObjectIdentifier(window)
            if let previous = previousAcceptsMouseMoved.removeValue(forKey: id) {
                window.acceptsMouseMovedEvents = previous
            }
        }
        previousAcceptsMouseMoved.removeAll()
    }

    private func dispatch(_ event: NSEvent) {
        var hit: AgentHookRowHoverTarget?
        for target in targets.allObjects {
            if target.contains(event) {
                hit = target
                break
            }
        }
        for target in targets.allObjects {
            target.apply(hovering: target === hit)
        }
    }
}

private final class AgentHookRowHoverTarget: NSView {
    var onHover: ((Bool) -> Void)?
    private var isHovered = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            AgentHookRowHoverRouter.shared.unregister(self)
        } else {
            AgentHookRowHoverRouter.shared.register(self)
        }
    }

    func teardown() {
        apply(hovering: false)
        AgentHookRowHoverRouter.shared.unregister(self)
    }

    func contains(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let target = hitTarget
        let point = target.convert(event.locationInWindow, from: nil)
        return target.bounds.contains(point)
    }

    func apply(hovering: Bool) {
        guard hovering != isHovered else { return }
        isHovered = hovering
        onHover?(hovering)
    }

    /// The padded row we own (overlay fills it), not the Form table cell.
    private var hitTarget: NSView {
        if bounds.width > 1, bounds.height > 1 {
            return self
        }
        return superview ?? self
    }
}

/// Pins the Aibo Actions preview when the in-flow band leaves through the top of the Form clip.
private struct AgentHookViewportTopExitMonitor: NSViewRepresentable {
    var onExited: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExited: onExited)
    }

    func makeNSView(context: Context) -> AgentHookViewportMonitorView {
        let view = AgentHookViewportMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: AgentHookViewportMonitorView, context: Context) {
        context.coordinator.onExited = onExited
        view.coordinator = context.coordinator
        context.coordinator.attach(from: view)
    }

    static func dismantleNSView(_ view: AgentHookViewportMonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onExited: (Bool) -> Void
        private var observer: NSObjectProtocol?
        private weak var clipView: NSClipView?
        private var lastExited: Bool?

        init(onExited: @escaping (Bool) -> Void) {
            self.onExited = onExited
        }

        func attach(from view: NSView) {
            guard let clip = view.enclosingScrollView?.contentView else { return }
            if clip === clipView { return }
            detach()
            clipView = clip
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let self, let view else { return }
                    self.report(from: view)
                }
            }
            report(from: view)
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            clipView = nil
        }

        func report(from view: NSView) {
            guard let clip = view.enclosingScrollView?.contentView else { return }
            let frame = view.convert(view.bounds, to: clip)
            let visible = clip.bounds
            let exitedTop: Bool
            if clip.isFlipped {
                let aboveTop = frame.minY < visible.minY
                let belowViewport = frame.minY > visible.maxY
                exitedTop = aboveTop && !belowViewport
            } else {
                let aboveTop = frame.maxY > visible.maxY
                let belowViewport = frame.maxY < visible.minY
                exitedTop = aboveTop && !belowViewport
            }
            guard exitedTop != lastExited else { return }
            lastExited = exitedTop
            onExited(exitedTop)
        }
    }
}

private final class AgentHookViewportMonitorView: NSView {
    var coordinator: AgentHookViewportTopExitMonitor.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.attach(from: self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        coordinator?.attach(from: self)
    }

    override func layout() {
        super.layout()
        coordinator?.report(from: self)
    }
}

/// System popup so `NSMenuDelegate.menu(_:willHighlight:)` can drive the sprite preview.
private struct AgentHookSpritePopUp: NSViewRepresentable {
    @Binding var selection: PetdexSpriteState
    var onHighlight: (PetdexSpriteState?) -> Void
    var onOpen: () -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selection: $selection,
            onHighlight: onHighlight,
            onOpen: onOpen,
            onClose: onClose
        )
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.autoenablesItems = false
        button.controlSize = .regular
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        for state in PetdexSpriteState.allCases {
            button.addItem(withTitle: localizedSpriteName(state))
            button.lastItem?.representedObject = state.rawValue
        }
        button.menu?.delegate = context.coordinator
        button.selectItem(withTitle: localizedSpriteName(selection))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onOpen = onOpen
        context.coordinator.onClose = onClose
        let title = localizedSpriteName(selection)
        if button.title != title {
            button.selectItem(withTitle: title)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var selection: Binding<PetdexSpriteState>
        var onHighlight: (PetdexSpriteState?) -> Void
        var onOpen: () -> Void
        var onClose: () -> Void

        init(
            selection: Binding<PetdexSpriteState>,
            onHighlight: @escaping (PetdexSpriteState?) -> Void,
            onOpen: @escaping () -> Void,
            onClose: @escaping () -> Void
        ) {
            self.selection = selection
            self.onHighlight = onHighlight
            self.onOpen = onOpen
            self.onClose = onClose
        }

        @objc func changed(_ sender: NSPopUpButton) {
            guard let raw = sender.selectedItem?.representedObject as? String,
                  let state = PetdexSpriteState(rawValue: raw)
            else { return }
            selection.wrappedValue = state
        }

        func menuWillOpen(_ menu: NSMenu) {
            onOpen()
        }

        func menuDidClose(_ menu: NSMenu) {
            onHighlight(nil)
            onClose()
        }

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            guard let raw = item?.representedObject as? String,
                  let state = PetdexSpriteState(rawValue: raw)
            else {
                onHighlight(nil)
                return
            }
            onHighlight(state)
        }
    }
}
