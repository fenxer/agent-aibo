import AppKit
import SwiftUI

struct StatusBubble: View {
    let item: StatusBubbleItem
    let placement: BubblePlacement
    /// Only the bubble nearest the pet keeps the popover arrow.
    var showsArrow: Bool = true
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
        let capsuleFill = ink
        let capsuleContent = prefersLightLabel ? Color.black : Color.white

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
            .modifier(DismissTapModifier(onDismiss: onDismiss))
    }

    @ViewBuilder
    private func bubbleContent(
        ink: Color,
        capsuleFill: Color,
        capsuleContent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasHeader {
                HStack(spacing: headerSpacing) {
                    if let projectName = item.projectName, !projectName.isEmpty {
                        Text(projectName)
                            .font(.system(size: 12))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                    if let modelName = item.modelName, !modelName.isEmpty {
                        Text(modelName)
                            .font(.system(size: 12)
                            .foregroundStyle(ink.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }

            // Capsule / status share line height; firstTextBaseline keeps glyphs aligned.
            HStack(alignment: .firstTextBaseline, spacing: headerSpacing) {
                agentCapsule(fill: capsuleFill, content: capsuleContent)
                statusText(ink: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func statusText(ink: Color) -> some View {
        let base = Self.strippingTrailingEllipsis(item.text)
        TimelineView(.animation(minimumInterval: Self.ellipsisInterval)) { context in
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

    private var hasHeader: Bool {
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

    /// White label when the effective tinted fill is dark; otherwise keep dark ink.
    private static func prefersLightLabel(
        tint: Color?,
        style: BubbleGlassStyle,
        colorScheme: ColorScheme
    ) -> Bool {
        guard let tint else { return false }
        let fillOpacity: Double = switch style {
        case .clear: 0.65
        case .regular: 0.45
        case .identity: 0.35
        }
        guard let rgb = NSColor(tint).usingColorSpace(.sRGB) else { return false }
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

#Preview("stacked") {
    StatusBubble(
        item: StatusBubbleItem(
            id: "2",
            text: "is waiting for you",
            lastEventAt: .now,
            agentName: "Codex",
            projectName: "aibo"
        ),
        placement: .top,
        showsArrow: false
    )
    .padding(40)
    .background(Color.secondary.opacity(0.25))
}

/// Applies a high-priority tap only when dismissible, so WindowDragGesture still works elsewhere.
private struct DismissTapModifier: ViewModifier {
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDismiss {
            content
                .highPriorityGesture(
                    TapGesture().onEnded { onDismiss() }
                )
                .accessibilityHint(String(localized: "Click to dismiss"))
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
