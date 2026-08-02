import AiboCore
import AppKit
import SwiftUI

struct StatusBubble: View {
    let item: StatusBubbleItem
    let placement: BubblePlacement
    /// Only the bubble nearest the pet keeps the popover arrow.
    var showsArrow: Bool = true
    /// When set, a tap activates the source app (local agent bubbles).
    var onActivate: (() -> Void)? = nil
    /// When set, a tap clears this bubble (e.g. `.failed`).
    var onDismiss: (() -> Void)? = nil
    /// Glass style / tint; defaults to live settings so previews can override.
    var glassStyle: BubbleGlassStyle = AppSettings.shared.bubbleGlassStyle
    var glassTint: Color? = AppSettings.shared.bubbleGlassTint

    @Environment(\.colorScheme) private var colorScheme

    private let arrowHeight: CGFloat = 6
    private let arrowWidth: CGFloat = 10
    private let cornerRadius: CGFloat = 16
    private let contentPadding: CGFloat = 12
    private let headerSpacing: CGFloat = 8
    private let sectionSpacing: CGFloat = 12
    private let capsuleIconSize: CGFloat = 18
    private let capsuleHeight: CGFloat = 22
    private let statusLineHeight: CGFloat = 22

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
        let capsuleFill = glassTint == nil ? Color.black : ink
        let capsuleContent =
            glassTint == nil
            ? Color.white
            : (prefersLightLabel ? Color.black : Color.white)

        bubbleContent(ink: ink, capsuleFill: capsuleFill, capsuleContent: capsuleContent)
            .padding(contentPadding)
            .padding(showsArrow ? Edge.Set(edge) : [], arrowHeight)
            .background {
                bubbleBackground(edge: edge)
            }
            .environment(
                \.backgroundProminence,
                prefersLightLabel ? .increased : .standard
            )
            // Cap width; pin content toward the pet so short copy doesn't float
            // in the middle of a bubbleMaxWidth-sized panel slot.
            .frame(maxWidth: 320, alignment: frameAlignment)
            // Don't compress wrapped text when a parent proposes a short height.
            .fixedSize(horizontal: false, vertical: true)
            // Stack left/right on the body edge, not the arrow tip.
            .alignmentGuide(.trailing) { d in
                showsArrow && placement == .left ? d[.trailing] - arrowHeight : d[.trailing]
            }
            .alignmentGuide(.leading) { d in
                showsArrow && placement == .right ? d[.leading] + arrowHeight : d[.leading]
            }
            .contentShape(Rectangle())
            .modifier(BubbleTapModifier(onActivate: onActivate, onDismiss: onDismiss))
    }

    @ViewBuilder
    private func bubbleContent(
        ink: Color,
        capsuleFill: Color,
        capsuleContent: Color
    ) -> some View {
        switch item.kind {
        case .agent:
            agentBubbleContent(ink: ink, capsuleFill: capsuleFill, capsuleContent: capsuleContent)
        case .webhook:
            webhookBubbleContent(ink: ink, capsuleFill: capsuleFill, capsuleContent: capsuleContent)
        case .warning:
            warningBubbleContent(ink: ink)
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
        HStack(spacing: 4) {
            if let iconAssetName = item.iconAssetName {
                Image(iconAssetName)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: capsuleIconSize, height: capsuleIconSize)
                    .foregroundStyle(content)
            }
            if !item.agentName.isEmpty {
                Text(item.agentName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(content)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(minHeight: capsuleHeight)
        .background(Capsule().fill(fill))
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
            arrowWidth: showsArrow ? arrowWidth : 0,
            arrowHeight: showsArrow ? arrowHeight : 0
        )
        // Keep text outside glassEffect — Liquid Glass foreground treatment
        // over glyphs causes heavy aliasing on a transparent NSPanel.
        //
        // `.identity` is a no-op glass, so color is fill-only.
        // `.regular.tint` does not visibly tint on a transparent NSPanel; put
        // the color behind the material instead (same pattern as Apple's
        // `.glassEffect(.clear).background(...)` example). `.clear.tint` still
        // comes from Glass.tint.
        if glassStyle == .identity {
            shape.fill(behindFill)
        } else {
            shape
                .fill(Color.clear)
                .glassEffect(configuredGlass, in: shape)
                .background {
                    shape.fill(behindFill)
                }
        }
    }

    private var configuredGlass: Glass {
        glassStyle.glass.tint(glassTint).interactive()
    }

    private var behindFill: Color {
        if let glassTint {
            switch glassStyle {
            case .identity:
                return glassTint.opacity(0.35)
            case .regular:
                return glassTint.opacity(0.45)
            case .clear:
                return Color.white.opacity(0.15)
            }
        }
        switch glassStyle {
        case .identity:
            return Color.primary.opacity(0.12)
        case .clear, .regular:
            return Color.white.opacity(0.2)
        }
    }

    /// Side closest to the pet — left bubble pins trailing, right pins leading.
    private var frameAlignment: Alignment {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
    }

    /// White label on dark glass / dark tinted fill; black ink otherwise.
    private static func prefersLightLabel(
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
        let luminance =
            0.2126 * srgbLinear(r)
            + 0.7152 * srgbLinear(g)
            + 0.0722 * srgbLinear(b)
        return luminance < 0.55
    }

    private static func srgbLinear(_ channel: CGFloat) -> Double {
        let c = Double(channel)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
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
            text: "needs your approval",
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
            text: "needs your approval",
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

/// High-priority tap for activate and/or dismiss, so WindowDragGesture still works elsewhere.
private struct BubbleTapModifier: ViewModifier {
    var onActivate: (() -> Void)?
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        if onActivate != nil || onDismiss != nil {
            content
                .highPriorityGesture(
                    TapGesture().onEnded {
                        onActivate?()
                        onDismiss?()
                    }
                )
                .accessibilityHint(accessibilityHint)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
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
