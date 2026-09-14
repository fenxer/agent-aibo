import AiboCore
import AppKit
import SwiftUI

struct StatusBubble: View {
    let item: StatusBubbleItem
    let placement: BubblePlacement
    /// Only the bubble nearest the aibo draws the popover triangle.
    var showsArrow: Bool = true
    /// Keep the arrow's layout slot so stacked rounded-rects share a width
    /// even when this bubble hides the triangle.
    var reservesArrowSlot: Bool = false
    /// When set, a tap activates the source app (local agent bubbles).
    var onActivate: (() -> Void)? = nil
    /// When set, a tap clears this bubble (e.g. `.failed`).
    var onDismiss: (() -> Void)? = nil
    /// Glass style / tint; defaults to live settings so previews can override.
    var glassStyle: BubbleGlassStyle = AppSettings.shared.bubbleGlassStyle
    var glassTint: Color? = AppSettings.shared.bubbleGlassTint

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.suppressBubbleGlass) private var suppressBubbleGlass
    private var runtime = AiboRuntime.shared
    /// Last measured status-face size; height so open / close animates between
    /// two concrete values, width so left/right inspect doesn't jump to 320.
    @State private var statusFaceHeight: CGFloat = 0
    @State private var statusFaceWidth: CGFloat = 0

    private let arrowHeight: CGFloat = 6
    private let arrowWidth: CGFloat = 10
    private let cornerRadius: CGFloat = 16
    private let contentPadding: CGFloat = 12
    private let headerSpacing: CGFloat = 8
    private let sectionSpacing: CGFloat = 12
    private let capsuleIconSize: CGFloat = 18
    private let capsuleHeight: CGFloat = 22
    private let statusLineHeight: CGFloat = 22

    private var showsInspectFace: Bool {
        item.kind == .agent && item.isInspecting
    }

    private var isSidePlacement: Bool {
        placement == .left || placement == .right
    }

    private var drawsArrow: Bool {
        showsArrow && !showsInspectFace
    }

    /// Left/right keep the arrow's layout slot while inspecting so the body
    /// width stays status-sized (triangle off, slot stays). Top/bottom drop
    /// the slot and grow vertically only.
    private var arrowSlotHeight: CGFloat {
        if showsInspectFace, !isSidePlacement { return 0 }
        return (showsArrow || reservesArrowSlot) ? arrowHeight : 0
    }

    var body: some View {
        let edge = placement.arrowEdge
        let prefersLightLabel = Self.prefersLightLabel(
            tint: glassTint,
            style: glassStyle,
            colorScheme: colorScheme
        )
        let ink = prefersLightLabel ? Color.white : Color.black
        // Untinted: keep a dark brand capsule (white label) in both schemes.
        // Tinted: invert the capsule against ink for contrast on the fill.
        // Per-agent custom capsule color (Agent Hook) overrides both.
        let defaultCapsuleFill = glassTint == nil ? Color.black : ink
        let defaultCapsuleContent =
            glassTint == nil
            ? Color.white
            : (prefersLightLabel ? Color.black : Color.white)
        let agentCapsule = Self.resolvedAgentCapsuleColors(
            agent: item.agent,
            defaultFill: defaultCapsuleFill,
            defaultContent: defaultCapsuleContent
        )

        chromedCard(edge: edge) {
            bubbleContent(
                ink: ink,
                capsuleFill: agentCapsule.fill,
                capsuleContent: agentCapsule.content,
                webhookCapsuleFill: defaultCapsuleFill,
                webhookCapsuleContent: defaultCapsuleContent,
                fillIsLight: prefersLightLabel
            )
        }
            // Right-click swaps the face in place; only the frame changes (no
            // transform — 3D / scale layers made the whole panel's glass rebuild
            // and every bubble blink). The stack in AiboView owns the animation
            // so pushed siblings move on the same curve.
            .alignmentGuide(.trailing) { d in
                arrowSlotHeight > 0 && placement == .left
                    ? d[.trailing] - arrowSlotHeight
                    : d[.trailing]
            }
            .alignmentGuide(.leading) { d in
                arrowSlotHeight > 0 && placement == .right
                    ? d[.leading] + arrowSlotHeight
                    : d[.leading]
            }
            .contentShape(Rectangle())
            .modifier(BubbleTapModifier(onActivate: onActivate, onDismiss: onDismiss))
            // Face / tap-target updates must not inherit the stack's poof.
            .transition(.identity)
    }

    /// Padding + popover glass around a face. Kept as one persistent view so a
    /// face swap animates the card frame instead of re-creating the chrome.
    @ViewBuilder
    private func chromedCard<Content: View>(
        edge: Edge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(contentPadding)
            .padding(arrowSlotHeight > 0 ? Edge.Set(edge) : [], arrowSlotHeight)
            .background {
                bubbleBackground(edge: edge)
            }
            .environment(
                \.backgroundProminence,
                Self.prefersLightLabel(
                    tint: glassTint,
                    style: glassStyle,
                    colorScheme: colorScheme
                ) ? .increased : .standard
            )
            // Cap width; pin content toward the aibo so short copy doesn't float
            // in the middle of a bubbleMaxWidth-sized panel slot.
            .frame(maxWidth: 320, alignment: frameAlignment)
            // Don't compress wrapped text when a parent proposes a short height.
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func bubbleContent(
        ink: Color,
        capsuleFill: Color,
        capsuleContent: Color,
        webhookCapsuleFill: Color,
        webhookCapsuleContent: Color,
        fillIsLight: Bool
    ) -> some View {
        switch item.kind {
        case .agent:
            agentFace(
                ink: ink,
                capsuleFill: capsuleFill,
                capsuleContent: capsuleContent,
                prefersLightInk: fillIsLight
            )
        case .webhook:
            webhookBubbleContent(
                ink: ink,
                capsuleFill: webhookCapsuleFill,
                capsuleContent: webhookCapsuleContent
            )
        case .warning:
            warningBubbleContent(ink: ink)
        case .onboarding:
            onboardingBubbleContent(ink: ink, fillIsLight: fillIsLight)
        }
    }

    @ViewBuilder
    private func agentBubbleContent(
        ink: Color,
        capsuleFill: Color,
        capsuleContent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasAgentHeader {
                HStack(spacing: headerSpacing) {
                    if let projectName = item.projectName, !projectName.isEmpty {
                        Text(projectName)
                            .font(.system(size: 12))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                    if let modelName = item.modelName, !modelName.isEmpty {
                        Text(modelName)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }

            // Capsule / status share line height; firstTextBaseline keeps glyphs aligned.
            // Attention CTA (approval / Cursor usingTool stall) keeps the agent capsule
            // and adds a trailing arrow.
            HStack(alignment: item.isAwaitingApproval ? .center : .firstTextBaseline, spacing: headerSpacing) {
                if item.isSubagent {
                    subagentCapsule(ink: ink)
                } else {
                    agentCapsule(fill: capsuleFill, content: capsuleContent)
                }
                statusText(ink: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isAwaitingApproval {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ink)
                        .symbolEffect(
                            .wiggle.byLayer,
                            options: .repeat(.periodic(delay: 2.0))
                        )
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Status stays in the tree (opacity only). Inspect is an overlay that
    /// does not affect intrinsic size. The outer height interpolates between
    /// the two faces so the card never dips (status removed) then grows —
    /// that dip is what made the near-aibo bubble overshoot its top.
    @ViewBuilder
    private func agentFace(
        ink: Color,
        capsuleFill: Color,
        capsuleContent: Color,
        prefersLightInk: Bool
    ) -> some View {
        let inspecting = item.isInspecting
        agentBubbleContent(
            ink: ink,
            capsuleFill: capsuleFill,
            capsuleContent: capsuleContent
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AgentStatusSizeKey.self,
                    value: proxy.size
                )
            }
        }
        .onPreferenceChange(AgentStatusSizeKey.self) { size in
            if size.height > 0 { statusFaceHeight = size.height }
            if size.width > 0 { statusFaceWidth = size.width }
        }
        .opacity(inspecting ? 0 : 1)
        // Height uses the stack's 0.35s curve; labels should be gone well
        // before the card finishes growing.
        .animation(.easeOut(duration: 0.12), value: inspecting)
        .allowsHitTesting(!inspecting)
        // Frame first so the overlay is proposed the inspect size. Overlay
        // on the status face made the JSON representable report height 0.
        .frame(
            width: sideLockedContentWidth,
            height: agentFaceHeight(inspecting: inspecting),
            alignment: .topLeading
        )
        .overlay(alignment: .topLeading) {
            if item.hookJSON != nil, !suppressBubbleGlass {
                inspectOverlay(ink: ink, prefersLightInk: prefersLightInk)
                    .opacity(inspecting ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: inspecting)
                    .allowsHitTesting(inspecting)
            }
        }
        .clipped()
    }

    private func agentFaceHeight(inspecting: Bool) -> CGFloat? {
        if inspecting { return inspectFaceHeight }
        return statusFaceHeight > 0 ? statusFaceHeight : nil
    }

    /// Left/right: pin inspect content to the status face width. Top/bottom
    /// may grow as wide as the 320 cap.
    private var sideLockedContentWidth: CGFloat? {
        guard isSidePlacement, showsInspectFace, statusFaceWidth > 0 else { return nil }
        return statusFaceWidth
    }

    /// Content height of the inspect face (no card padding). Matches the
    /// panel's `estimatedHookInspectHeight` minus padding.
    private var inspectFaceHeight: CGFloat {
        inspectJSONHeight()
            + HookInspectLayout.sectionSpacing
            + HookInspectLayout.buttonRowHeight
    }

    private func inspectJSONHeight() -> CGFloat {
        let pretty = HookPayloadJSON.prettyPrinted(item.hookJSON ?? "")
        let width = max(
            1,
            sideLockedContentWidth ?? (320 - contentPadding * 2)
        )
        let font = NSFont.monospacedSystemFont(
            ofSize: HookInspectLayout.jsonFontSize,
            weight: .regular
        )
        let used = ceil(
            (pretty as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        return min(HookInspectLayout.jsonMaxHeight, max(14, used))
    }

    @ViewBuilder
    private func inspectOverlay(ink: Color, prefersLightInk: Bool) -> some View {
        VStack(alignment: .leading, spacing: HookInspectLayout.sectionSpacing) {
            InspectJSONScrollView(
                text: HookPayloadJSON.prettyPrinted(item.hookJSON ?? ""),
                prefersLightInk: prefersLightInk,
                maxHeight: HookInspectLayout.jsonMaxHeight
            )
            .frame(maxWidth: .infinity)
            .frame(height: inspectJSONHeight())
            .animation(nil, value: item.isInspecting)

            HStack(spacing: HookInspectLayout.buttonSpacing) {
                inspectCopyChip(ink: ink)
                inspectChipLabel(String(localized: "Close Bubble"), ink: ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func inspectCopyChip(ink: Color) -> some View {
        let copied = runtime.inspectJustCopiedID == item.id
        inspectChipLabel(
            copied ? String(localized: "Copied") : String(localized: "Copy"),
            ink: ink,
            widthReserve: String(localized: "Copied")
        )
    }

    /// Capsule Liquid Glass chip. `widthReserve` keeps Copy → Copied from jumping.
    private func inspectChipLabel(
        _ title: String,
        ink: Color,
        widthReserve: String? = nil
    ) -> some View {
        let prefersLight = Self.prefersLightLabel(
            tint: glassTint,
            style: glassStyle,
            colorScheme: colorScheme
        )
        return ZStack {
            if let widthReserve {
                Text(widthReserve)
                    .font(.system(size: 12))
                    .hidden()
            }
            Text(title)
                .font(.system(size: 12))
        }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .frame(height: HookInspectLayout.buttonChrome)
            .background { inspectChipGlass }
            .environment(\.backgroundProminence, prefersLight ? .increased : .standard)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.15), value: title)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var inspectChipGlass: some View {
        Self.chromeMaterial(
            Capsule(),
            style: .clear,
            tint: glassTint,
            suppressGlass: suppressBubbleGlass
        )
    }

    @ViewBuilder
    private func webhookBubbleContent(
        ink: Color,
        capsuleFill: Color,
        capsuleContent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: headerSpacing) {
                if !item.agentName.isEmpty {
                    Text(item.agentName)
                        .font(.system(size: 12))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
                // Keep aging while the bubble stays up (nudge to click / dismiss).
                // Minute cadence matches RelativeDateTimeFormatter granularity —
                // avoid .animation (would wake every display refresh).
                TimelineView(.everyMinute) { context in
                    Text(Self.relativeTimeString(from: item.lastEventAt, relativeTo: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.6))
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: headerSpacing) {
                if let statusLabel = item.statusLabel, !statusLabel.isEmpty {
                    webhookStatusCapsule(
                        status: statusLabel,
                        fill: capsuleFill,
                        content: capsuleContent
                    )
                }
                statusText(ink: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func onboardingBubbleContent(ink: Color, fillIsLight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasAgentHeader {
                HStack(spacing: headerSpacing) {
                    if let projectName = item.projectName, !projectName.isEmpty {
                        Text(projectName)
                            .font(.system(size: 12))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                    if let modelName = item.modelName, !modelName.isEmpty {
                        Text(modelName)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }

            Text(item.text)
                .font(.system(size: 14, weight: .regular))
                .lineHeight(.exact(points: statusLineHeight))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            let tour = OnboardingController.shared
            if tour.isActive, tour.step == .chooseAibo {
                OnboardingChooseAiboContent(
                    ink: ink,
                    onInk: fillIsLight ? Color.black : Color.white,
                    fillIsLight: fillIsLight
                )
            } else if tour.isActive, tour.step == .agentHook {
                OnboardingAgentHookContent(ink: ink)
            }
        }
    }

    @ViewBuilder
    private func warningBubbleContent(ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: headerSpacing) {
                Text(String(localized: "Warning"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                TimelineView(.everyMinute) { context in
                    Text(Self.relativeTimeString(from: item.lastEventAt, relativeTo: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.6))
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: headerSpacing) {
                warningIconCapsule()
                statusText(ink: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Fixed red capsule with warning triangle only (ignores glass tint / brand capsule).
    @ViewBuilder
    private func warningIconCapsule() -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .padding(.horizontal, 8)
            .frame(minHeight: capsuleHeight)
            .background(Capsule().fill(Color.red))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func statusText(ink: Color) -> some View {
        if item.animatesEllipsis {
            let base = Self.strippingTrailingEllipsis(item.text)
            TimelineView(.periodic(from: Self.ellipsisEpoch, by: Self.ellipsisInterval)) { context in
                let count = Int(context.date.timeIntervalSinceReferenceDate / Self.ellipsisInterval) % 3 + 1
                let dots = String(repeating: ".", count: count)
                // Layout against the widest form ("...") so 1↔2↔3 dots don’t reflow.
                Text(base + "...")
                    .font(.system(size: 14, weight: .regular))
                    .lineHeight(.exact(points: statusLineHeight))
                    .hidden()
                    .overlay(alignment: .topLeading) {
                        Text(base + dots)
                            .font(.system(size: 14, weight: .regular))
                            .lineHeight(.exact(points: statusLineHeight))
                            .foregroundStyle(ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel(base + dots)
            }
        } else {
            Text(item.text)
                .font(.system(size: 14, weight: .regular))
                .lineHeight(.exact(points: statusLineHeight))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Strip trailing ASCII / typographic ellipsis so the animated dots own the ending.
    private static func strippingTrailingEllipsis(_ text: String) -> String {
        var result = text
        while result.hasSuffix("…") {
            result.removeLast()
        }
        while result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }

    private static let ellipsisInterval: TimeInterval = 0.45

    /// `.animation` wakes the view graph on every display refresh (60–120 Hz) and
    /// only then filters by `minimumInterval`, so cycling three dots cost a full
    /// re-layout of the bubble text ~120 times a second. A periodic schedule wakes
    /// only when the dots actually change. Shared across bubbles so they stay in phase.
    private static let ellipsisEpoch = Date()

    private var hasAgentHeader: Bool {
        let hasProject = !(item.projectName ?? "").isEmpty
        let hasModel = !(item.modelName ?? "").isEmpty
        return hasProject || hasModel
    }

    @ViewBuilder
    private func agentCapsule(fill: Color, content: Color) -> some View {
        HStack(spacing: 0) {
            if let iconAssetName = item.iconAssetName {
                Image(iconAssetName)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: capsuleIconSize, height: capsuleIconSize)
                    .foregroundStyle(content)
                    .padding(.trailing, 4)
            }
            if !item.agentName.isEmpty {
                Text(item.agentName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(content)
                    .lineLimit(1)
            }
            if let progress = item.planProgress, progress.total > 0 {
                CapsulePlanProgressView(
                    current: progress.current,
                    total: progress.total,
                    completed: progress.completed,
                    color: content
                )
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(minHeight: capsuleHeight)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .background {
            capsuleBackground(fill: fill)
        }
    }

    @ViewBuilder
    private func capsuleBackground(fill: Color) -> some View {
        let plan = item.planProgress
        let shaderAgent = item.agent.flatMap { $0.supportsPlanProgress ? $0 : nil } ?? .codex
        let usesShader = plan.map { $0.total > 0 } == true
            && (item.forcesPlanProgressShader
                || item.agent.map { AppSettings.shared.planProgressShaderEnabled(for: $0) } == true)
        Group {
            if usesShader, let plan {
                CapsulePlanShaderBackground(
                    progress: plan.fraction,
                    track: fill,
                    primary: AppSettings.shared.resolvedPlanProgressShaderPrimary(for: shaderAgent)
                )
            } else {
                Capsule().fill(fill)
            }
        }
        .clipShape(Capsule())
    }

    /// Outline capsule: 1pt dashed border (marching ants), no fill, label “Subagent”.
    @ViewBuilder
    private func subagentCapsule(ink: Color) -> some View {
        HStack(spacing: 4) {
            if let iconAssetName = item.iconAssetName {
                Image(iconAssetName)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: capsuleIconSize, height: capsuleIconSize)
                    .foregroundStyle(ink)
            }
            Text(item.agentName.isEmpty ? "Subagent" : item.agentName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(minHeight: capsuleHeight)
        .overlay {
            MarchingAntsCapsuleStroke(stroke: ink)
        }
    }

    /// Webhook status capsule: symmetric 8pt horizontal padding (no icon).
    @ViewBuilder
    private func webhookStatusCapsule(status: String, fill: Color, content: Color) -> some View {
        Text(status)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(content)
            .lineLimit(1)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .padding(.horizontal, 8)
            .frame(minHeight: capsuleHeight)
            .background(Capsule().fill(fill))
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        return formatter
    }()

    private static func relativeTimeString(from date: Date, relativeTo now: Date) -> String {
        // TimelineView may re-evaluate on unrelated panel refreshes; showing
        // seconds makes the label jitter (and reprobes used to reset lastEventAt).
        // Under one minute, keep a stable phrase; then use minute-scale relatives.
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return String(localized: "just now")
        }
        return relativeTimeFormatter.localizedString(for: date, relativeTo: now)
    }

    @ViewBuilder
    private func bubbleBackground(edge: Edge) -> some View {
        // Same shape for arrow / no-arrow so stacked corner arcs match
        // (RoundedRectangle .continuous looks softer than circular Path arcs).
        let shape = PopoverBubbleShape(
            arrowEdge: edge,
            cornerRadius: cornerRadius,
            arrowWidth: drawsArrow ? arrowWidth : 0,
            arrowHeight: arrowSlotHeight
        )
        // Keep text outside glassEffect — Liquid Glass foreground treatment
        // over glyphs causes heavy aliasing on a transparent NSPanel.
        //
        // `.identity` is a no-op glass, so color is fill-only.
        // `.regular.tint` does not visibly tint on a transparent NSPanel; put
        // the color behind the material instead (same pattern as Apple's
        // `.glassEffect(.clear).background(...)` example). `.clear.tint` still
        // comes from Glass.tint.
        //
        // Branching here on purpose: poof must unmount NSGlassEffectView, not
        // fade it. A ternary on Glass would leave the platform view in place.
        Self.chromeMaterial(
            shape,
            style: glassStyle,
            tint: glassTint,
            suppressGlass: suppressBubbleGlass
        )
    }

    static func configuredGlass(style: BubbleGlassStyle, tint: Color?) -> Glass {
        style.glass.tint(tint).interactive()
    }

    @ViewBuilder
    static func chromeMaterial<S: Shape>(
        _ shape: S,
        style: BubbleGlassStyle,
        tint: Color?,
        suppressGlass: Bool
    ) -> some View {
        if suppressGlass {
            shape.fill(Color.clear)
        } else if style == .identity {
            shape.fill(behindFill(style: style, tint: tint))
        } else {
            shape
                .fill(Color.clear)
                .glassEffect(configuredGlass(style: style, tint: tint), in: shape)
                .background {
                    shape.fill(behindFill(style: style, tint: tint))
                }
        }
    }

    static func behindFill(style: BubbleGlassStyle, tint: Color?) -> Color {
        if let tint {
            switch style {
            case .identity:
                return tint.opacity(0.35)
            case .regular:
                return tint.opacity(0.45)
            case .clear:
                return Color.white.opacity(0.15)
            }
        }
        switch style {
        case .identity:
            return Color.primary.opacity(0.12)
        case .clear, .regular:
            return Color.white.opacity(0.2)
        }
    }

    /// Side closest to the aibo — left bubble pins trailing, right pins leading.
    private var frameAlignment: Alignment {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
    }

    /// White label on dark glass / dark tinted fill; black ink otherwise.
    static func prefersLightLabel(
        tint: Color?,
        style: BubbleGlassStyle,
        colorScheme: ColorScheme
    ) -> Bool {
        // No custom tint: Liquid Glass follows system appearance.
        guard let tint else { return colorScheme == .dark }
        let fillOpacity: Double = switch style {
        case .clear: 0.65
        case .regular: 0.45
        case .identity: 0.35
        }
        guard let rgb = NSColor(tint).usingColorSpace(.sRGB) else {
            return colorScheme == .dark
        }
        let backdrop = colorScheme == .dark ? 0.18 : 0.92
        let r = rgb.redComponent * fillOpacity + backdrop * (1 - fillOpacity)
        let g = rgb.greenComponent * fillOpacity + backdrop * (1 - fillOpacity)
        let b = rgb.blueComponent * fillOpacity + backdrop * (1 - fillOpacity)
        return relativeLuminance(r: r, g: g, b: b) < 0.55
    }

    /// Agent capsule fill/content: per-agent custom color wins over glass defaults.
    private static func resolvedAgentCapsuleColors(
        agent: AgentKind?,
        defaultFill: Color,
        defaultContent: Color
    ) -> (fill: Color, content: Color) {
        guard let agent,
              let custom = AppSettings.shared.agentCapsuleColor(for: agent)
        else {
            return (defaultFill, defaultContent)
        }
        let content = prefersLightContent(on: custom) ? Color.white : Color.black
        return (custom, content)
    }

    /// White glyph/label on dark capsule fills; black on light fills.
    private static func prefersLightContent(on fill: Color) -> Bool {
        guard let rgb = NSColor(fill).usingColorSpace(.sRGB) else { return true }
        return relativeLuminance(
            r: rgb.redComponent,
            g: rgb.greenComponent,
            b: rgb.blueComponent
        ) < 0.55
    }

    private static func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> Double {
        0.2126 * srgbLinear(r)
            + 0.7152 * srgbLinear(g)
            + 0.0722 * srgbLinear(b)
    }

    private static func srgbLinear(_ channel: CGFloat) -> Double {
        let c = Double(channel)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}

private struct AgentStatusSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(
            width: max(value.width, next.width),
            height: max(value.height, next.height)
        )
    }
}

#Preview("top") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "1",
            text: "is thinking",
            lastEventAt: .now,
            agentName: "Cursor",
            iconAssetName: "cursor",
            projectName: "design-fragments",
            modelName: "Grok 4.5 High Fast"
        ),
        placement: .top
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

#Preview("subagent") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "sub",
            text: "is thinking",
            lastEventAt: .now,
            agentName: "Subagent",
            iconAssetName: "cursor",
            projectName: "design-fragments",
            modelName: "Grok 4.5 High Fast",
            isSubagent: true
        ),
        placement: .top
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

#Preview("approval") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "approval",
            text: "got stuck?",
            lastEventAt: .now,
            animatesEllipsis: false,
            isAwaitingApproval: true,
            agentName: "Codex",
            iconAssetName: "codex",
            projectName: "aibo",
            agent: .codex
        ),
        placement: .top
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

#Preview("stacked") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "2",
            text: "got stuck?",
            lastEventAt: .now,
            animatesEllipsis: false,
            isAwaitingApproval: true,
            agentName: "Codex",
            iconAssetName: "codex",
            projectName: "aibo"
        ),
        placement: .top,
        showsArrow: false
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

#Preview("plan progress") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "plan",
            text: "is thinking",
            lastEventAt: .now,
            agentName: "Codex",
            iconAssetName: "codex",
            projectName: "design-fragments",
            modelName: "Grok 4.5 High Fast",
            agent: .codex,
            planProgress: AgentPlanProgress(current: 1, total: 3, completed: 0)
        ),
        placement: .top
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

#Preview("webhook") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "webhook:1",
            text: "deployed main@abc1234",
            lastEventAt: .now.addingTimeInterval(-3 * 60 * 60),
            kind: .webhook,
            animatesEllipsis: false,
            agentName: "Deploy Bot",
            statusLabel: "FINISHED"
        ),
        placement: .top
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

#Preview("warning") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "tunnel:health",
            text: "Tunnel is down, take a look!",
            lastEventAt: .now.addingTimeInterval(-3 * 60 * 60),
            kind: .warning,
            isDismissible: true,
            animatesEllipsis: false
        ),
        placement: .top
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

/// Codex checklist inside the agent capsule: bar + ring + `current/total`.
/// Leading 8pt is owned here so the parent HStack can use spacing 0 after the name.
private struct CapsulePlanProgressView: View {
    let current: Int
    let total: Int
    let completed: Int
    let color: Color

    private let barHeight: CGFloat = 10
    private let ringSize: CGFloat = 12
    private let ringLineWidth: CGFloat = 1.5

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color.opacity(0.3))
                .frame(width: 1, height: barHeight)
                .padding(.horizontal, 8)
            ZStack {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: ringLineWidth)
                if fraction > 0 {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: ringSize, height: ringSize)
            Text(verbatim: "\(current)/\(total)")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(color)
                .monospacedDigit()
                .fixedSize()
                .padding(.leading, 4)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(Text(verbatim: "\(current)/\(total)"))
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(completed) / CGFloat(total))
    }
}

/// High-priority tap for activate and/or dismiss (wins over any residual drag gestures).
private struct BubbleTapModifier: ViewModifier {
    var onActivate: (() -> Void)?
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        // One tree for both faces. `if tappable { gesture } else { content }`
        // remounts the whole card; the stack's poof then plays on inspect toggle.
        let tappable = onActivate != nil || onDismiss != nil
        content
            .highPriorityGesture(
                TapGesture().onEnded {
                    onActivate?()
                    onDismiss?()
                },
                isEnabled: tappable
            )
            .accessibilityHint(tappable ? accessibilityHint : "")
            .accessibilityAddTraits(tappable ? .isButton : [])
    }

    private var accessibilityHint: String {
        switch (onActivate != nil, onDismiss != nil) {
        case (true, true):
            String(localized: "Click to switch to app and dismiss")
        case (true, false):
            String(localized: "Click to switch to app")
        case (false, true):
            String(localized: "Click to dismiss")
        case (false, false):
            ""
        }
    }
}

/// 1pt dashed capsule stroke with a looping dash-phase (“marching ants”).
/// Driven by Core Animation — not display-link polling.
private struct MarchingAntsCapsuleStroke: View {
    let stroke: Color
    /// Dash + gap; phase animates by one full cycle length.
    private let dash: [CGFloat] = [3.5, 2.5]
    @State private var phase: CGFloat = 0

    private var cycleLength: CGFloat {
        dash.reduce(0, +)
    }

    var body: some View {
        Capsule()
            .strokeBorder(
                stroke,
                style: StrokeStyle(lineWidth: 1, dash: dash, dashPhase: phase)
            )
            .onAppear {
                phase = 0
                withAnimation(.linear(duration: 0.55).repeatForever(autoreverses: false)) {
                    phase = -cycleLength
                }
            }
    }
}
