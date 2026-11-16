import AppKit
import SwiftUI

struct ToolsSettingsPane: View {
    private enum Page {
        case keystroke
        case hookCleanup
    }

    @State private var page: Page?
    @State private var navigator = SettingsNavigator.shared

    var body: some View {
        switch page {
        case .keystroke:
            KeystrokeSettingsView { page = nil }
        case .hookCleanup:
            HookCleanupSettingsView { page = nil }
        case nil:
            toolsGrid
        }
    }

    private var toolsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ToolsIntroRow()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                ToolCardGrid {
                    ToolCoverCard(
                        cover: "ToolCoverKey",
                        title: String(localized: "Keystroke"),
                        detail: String(localized: "Shows the keys you press beside Aibo.")
                    ) {
                        page = .keystroke
                    }
                    ToolCoverCard(
                        cover: "ToolCoverCleanup",
                        title: String(localized: "Hook Cleanup"),
                        detail: String(localized: "See which apps left hooks for the agents on this Mac")
                    ) {
                        page = .hookCleanup
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Tools"))
        .onAppear { openPendingHookCleanup() }
        .onChange(of: navigator.pendingToolsHookCleanup) { _, isPending in
            guard isPending else { return }
            openPendingHookCleanup()
        }
    }

    private func openPendingHookCleanup() {
        guard navigator.consumePendingToolsHookCleanup() else { return }
        page = .hookCleanup
    }

    /// Same gray as a grouped form section, lighter than `secondarySystemFill`.
    fileprivate static let cardFill = Color(nsColor: .underPageBackgroundColor)
}

private struct KeystrokeSettingsView: View {
    var onBack: () -> Void

    @Bindable private var settings = AppSettings.shared
    private var keystrokes = KeystrokeMonitor.shared

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Keystroke"))
                        Text(String(localized: "Shows the keys you press beside Aibo."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle(String(localized: "Keystroke"), isOn: $settings.keystrokeOverlayEnabled)
                        .labelsHidden()
                }
                if settings.keystrokeOverlayEnabled {
                    LabeledContent {
                        stayTimeField
                    } label: {
                        settingLabel(
                            String(localized: "Stay Time"),
                            detail: String(localized: "0 seconds keeps the keys on screen until the next group replaces them.")
                        )
                    }
                    .labeledContentStyle(KeystrokeSettingLabelStyle())
                    LabeledContent {
                        maxKeysField
                    } label: {
                        settingLabel(
                            String(localized: "Max Keys"),
                            detail: String(localized: "0 keeps every key from the same interval in one group, up to 10 rows.")
                        )
                    }
                    .labeledContentStyle(KeystrokeSettingLabelStyle())
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Other bubbles stay hidden while this is on."))
                    if settings.keystrokeOverlayEnabled, keystrokes.accessibilityTrusted == false {
                        Text(String(localized: "Aibo needs Accessibility access to see keys you press in other apps."))
                        Button(String(localized: "Open Accessibility Settings")) {
                            Self.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(
            title: String(localized: "Keystroke"),
            canGoBack: true,
            onBack: onBack
        )
    }

    private var stayTimeField: some View {
        HStack(spacing: 6) {
            TextField(
                String(localized: "Stay Time"),
                value: $settings.keystrokeLingerSeconds,
                format: .number.grouping(.never)
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 64)
            Text(String(localized: "keystroke.linger.unit", defaultValue: "s"))
                .foregroundStyle(.secondary)
        }
    }

    private var maxKeysField: some View {
        TextField(
            String(localized: "Max Keys"),
            value: $settings.keystrokeMaxCount,
            format: .number.grouping(.never)
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 64)
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ToolsIntroRow: View {
    private let side: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            Image("ToolIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Tools"))
                    .font(.body.weight(.semibold))
                Text(String(localized: "More ways to use Aibo as an input"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Form labels align to the title baseline, so a subtitle leaves the field high.
private struct KeystrokeSettingLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}

/// Covers are exported at 160pt tall. The well grows wider, up to 210, and the
/// picture stays at that height in the vertical center.
private struct ToolCoverCard: View {
    var cover: String
    var title: String
    var detail: String
    var action: () -> Void

    private let coverHeight: CGFloat = 160
    private let coverMaxWidth: CGFloat = 210
    private let pictureWidth: CGFloat = 210

    var body: some View {
        ToolCardHeight {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Image(cover)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: pictureWidth, height: coverHeight)
                }
                .frame(maxWidth: coverMaxWidth)
                .frame(height: coverHeight)
                .frame(maxWidth: .infinity)
                .clipped()

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        }
        .background(ToolsSettingsPane.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Fills a finite row height so cards in one row match. An unspecified or
/// infinite proposal stays at the content height, so the settings window
/// does not grow to fit it.
private struct ToolCardHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let ideal = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let width = proposal.width ?? ideal.width
        let height: CGFloat
        if let proposed = proposal.height, proposed.isFinite, proposed >= ideal.height {
            height = proposed
        } else {
            height = ideal.height
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}

/// One more column once another max-width card and its 8pt gap fit.
/// Max card = 210pt cover + 12pt padding on each side.
private struct ToolCardGrid: Layout {
    var gap: CGFloat = 8
    var maxCardWidth: CGFloat = 210 + 12 * 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = (proposal.width?.isFinite == true) ? proposal.width! : maxCardWidth
        let columns = columnCount(for: width)
        let cardWidth = cardWidth(total: width, columns: columns)
        let rows = rowCount(subviews.count, columns: columns)
        let height = (0..<rows).reduce(CGFloat(0)) { partial, row in
            partial + rowHeight(row, columns: columns, cardWidth: cardWidth, subviews: subviews)
        } + gap * CGFloat(max(0, rows - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let columns = columnCount(for: bounds.width)
        let cardWidth = cardWidth(total: bounds.width, columns: columns)
        var y = bounds.minY
        let rows = rowCount(subviews.count, columns: columns)
        for row in 0..<rows {
            let height = rowHeight(row, columns: columns, cardWidth: cardWidth, subviews: subviews)
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { return }
                let x = bounds.minX + CGFloat(column) * (cardWidth + gap)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: cardWidth, height: height)
                )
            }
            y += height + gap
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width + gap) / (maxCardWidth + gap)))
    }

    private func cardWidth(total: CGFloat, columns: Int) -> CGFloat {
        let gaps = gap * CGFloat(columns - 1)
        return (total - gaps) / CGFloat(columns)
    }

    private func rowCount(_ items: Int, columns: Int) -> Int {
        Int(ceil(Double(items) / Double(columns)))
    }

    private func rowHeight(_ row: Int, columns: Int, cardWidth: CGFloat, subviews: Subviews) -> CGFloat {
        var height: CGFloat = 0
        for column in 0..<columns {
            let index = row * columns + column
            guard index < subviews.count else { break }
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: cardWidth, height: nil))
            if size.height.isFinite {
                height = max(height, size.height)
            }
        }
        return height
    }
}
