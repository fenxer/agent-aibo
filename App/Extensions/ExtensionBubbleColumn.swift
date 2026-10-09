import AiboCore
import AppKit
import SwiftUI

enum ExtensionBubbleMetrics {
    static let cardWidth: CGFloat = 300
    static let formControlHeight: CGFloat = 32
    static let formPadding: CGFloat = 12
    static let statusSpacing: CGFloat = 10
    /// Default plugin tile beside the 14pt plugin name.
    static let pluginIconSize: CGFloat = 24
    static let pluginIconCornerRadius: CGFloat = 6
    static let pluginHeaderHeight: CGFloat = pluginIconSize
    static let pluginHeaderSpacing: CGFloat = 8
    /// Result / error copy scrolls inside this, so a long translation cannot stretch the card.
    static let resultTextMaxHeight: CGFloat = 140

    /// Gap between prompt plates, and the plate corner radius.
    static let groupSpacing: CGFloat = 12
    static let groupCornerRadius: CGFloat = 12
    /// Standard plate / row. Multiline text and the image tile grow past this.
    static let rowHeight: CGFloat = 44
    static let rowPadding: CGFloat = 10
    static let arrowExtent: CGFloat = 6
    static let arrowWidth: CGFloat = 10
    static let fieldFontSize: CGFloat = 14
    static let inputCornerRadius: CGFloat = 6
    static let labelLineHeight: CGFloat = 18
    static let multilineSpacing: CGFloat = 8
    static let multilineWellHeight: CGFloat = 88
    static let textGroupPadding: CGFloat = 10
    static let imageTile: CGFloat = 52
    static let imageRowHeight: CGFloat = 76
    static let buttonRowHeight: CGFloat = 32
    static let separatorHeight: CGFloat = 1

    static var multilineRowHeight: CGFloat {
        textGroupPadding * 2 + labelLineHeight + multilineSpacing + multilineWellHeight
    }

    static func controlHeight(_ kind: ExtensionPromptControl.Kind) -> CGFloat {
        switch kind {
        case .text: multilineRowHeight
        case .image: imageRowHeight
        default: rowHeight
        }
    }

    static func groupHeight(kinds: [ExtensionPromptControl.Kind]) -> CGFloat {
        let rows = kinds.reduce(CGFloat(0)) { $0 + controlHeight($1) }
        return rows + CGFloat(max(0, kinds.count - 1)) * separatorHeight
    }

    static func promptStackHeight(kinds: [[ExtensionPromptControl.Kind]]) -> CGFloat {
        var height = pluginHeaderHeight
        for group in kinds {
            height += groupSpacing
            height += groupHeight(kinds: group)
        }
        height += groupSpacing + buttonRowHeight
        return height
    }

    static func promptCardHeight(kinds: [[ExtensionPromptControl.Kind]]) -> CGFloat {
        formPadding * 2 + promptStackHeight(kinds: kinds)
    }

    static func promptHeight(kinds: [[ExtensionPromptControl.Kind]]) -> CGFloat {
        promptCardHeight(kinds: kinds)
    }

    static func statusCardHeight(text: String) -> CGFloat {
        formPadding * 2
            + pluginHeaderHeight
            + pluginHeaderSpacing
            + textBlockHeight(text)
            + statusSpacing
            + formControlHeight
    }

    static func statusHeight(text: String) -> CGFloat {
        statusCardHeight(text: text)
    }

    static let runningWellPadding: CGFloat = 8
    static let dependencyTitleHeight: CGFloat = 18
    static let dependencyRowHeight: CGFloat = 52
    static let dependencyRowSpacing: CGFloat = 8

    static func runningCardHeight(text: String) -> CGFloat {
        formPadding * 2
            + pluginHeaderHeight
            + pluginHeaderSpacing
            + runningWellPadding * 2
            + runningTextHeight(text)
    }

    /// The running note is one short line in the mockups. Don't reuse the result
    /// block's 36pt floor or the card grows a blank band under the well.
    static func runningTextHeight(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fieldFontSize)
        let width = cardWidth - formPadding * 2 - runningWellPadding * 2
        let measured = ceil(
            (text as NSString).boundingRect(
                with: NSSize(width: max(1, width), height: 800),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        return min(resultTextMaxHeight, max(labelLineHeight, measured))
    }

    static func dependencyCardHeight(count: Int) -> CGFloat {
        let rows = CGFloat(max(count, 1)) * dependencyRowHeight
            + CGFloat(max(0, count - 1)) * dependencyRowSpacing
        return formPadding * 2
            + pluginHeaderHeight
            + pluginHeaderSpacing
            + dependencyTitleHeight
            + dependencyRowSpacing
            + rows
            + statusSpacing
            + formControlHeight
    }

    static func textBlockHeight(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14)
        let width = cardWidth - formPadding * 2
        let measured = ceil(
            (text as NSString).boundingRect(
                with: NSSize(width: max(1, width), height: 800),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        return min(resultTextMaxHeight, max(36, measured))
    }
}

struct ExtensionBubbleColumn: View {
    var placement: BubblePlacement
    /// Arrow only when this card is the one beside the pet.
    var showsArrow: Bool = true
    var center: ExtensionCenter

    @Environment(\.suppressBubbleGlass) private var suppressBubbleGlass

    private var session: ExtensionPromptSession? { center.session }

    var body: some View {
        let alignment: HorizontalAlignment = switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
        VStack(alignment: alignment, spacing: 4) {
            if let session {
                cards(session: session)
            }
        }
        // No arrow on this card: keep the same pet-side slot the bubble below
        // uses for its triangle, so the two bodies line up.
        .padding(arrowSlotEdges, showsArrow ? 0 : ExtensionBubbleMetrics.arrowExtent)
        .frame(width: 320, alignment: frameAlignment)
        .buttonBorderShape(.capsule)
    }

    /// Pet side only. Left placement reserves the trailing edge; right reserves leading.
    private var arrowSlotEdges: Edge.Set {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: []
        }
    }

    private var frameAlignment: Alignment {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
    }

    /// Shadow room under the glass. `showsArrow` is true only when no hook
    /// bubble is under this card (side). Down placement is always the bottom edge.
    private var bottomShadowRoom: CGFloat {
        AiboAppearance.pluginBottomShadowRoom(
            placement: placement,
            hookBubbleCount: showsArrow ? 0 : 1
        )
    }

    @ViewBuilder
    private func cards(session: ExtensionPromptSession) -> some View {
        switch session.phase {
        case .editing:
            formCard(session)
        case .running(let message):
            card(height: ExtensionBubbleMetrics.runningCardHeight(text: message), arrow: showsArrow) {
                ExtensionRunningCard(
                    name: session.pluginName,
                    directory: pluginDirectory(session),
                    icon: pluginIcon(session),
                    message: message,
                    onClose: { center.cancelSession() }
                )
            }
        case .result(let summary, _):
            outcomeCard(session, kind: .completed, text: summary, copiesIssue: false)
        case .failed(let message, _):
            outcomeCard(session, kind: .failed, text: message, copiesIssue: true)
        case .notice(let summary, _):
            outcomeCard(session, kind: .warning, text: summary, copiesIssue: true)
        case .dependency(let issues):
            card(
                height: ExtensionBubbleMetrics.dependencyCardHeight(count: issues.count),
                arrow: showsArrow
            ) {
                ExtensionDependencyCard(
                    name: session.pluginName,
                    directory: pluginDirectory(session),
                    icon: pluginIcon(session),
                    rows: dependencyRows(issues),
                    installingID: ExtensionCatalogClient.shared.installingID,
                    onInstall: { center.installDependency(catalogID: $0) },
                    onEnabled: { enabled, pluginID in
                        center.setDependencyEnabled(enabled, pluginID: pluginID)
                    },
                    onCopy: { center.copyResult() },
                    onClose: { center.cancelSession() }
                )
            }
        }
    }

    private func outcomeCard(
        _ session: ExtensionPromptSession,
        kind: ExtensionOutcomeKind,
        text: String,
        copiesIssue: Bool
    ) -> some View {
        card(height: ExtensionBubbleMetrics.statusCardHeight(text: text), arrow: showsArrow) {
            ExtensionOutcomeCard(
                name: session.pluginName,
                directory: pluginDirectory(session),
                icon: pluginIcon(session),
                kind: kind,
                text: text,
                copiesIssue: copiesIssue,
                onCopy: { center.copyResult() },
                onClose: { center.cancelSession() }
            )
        }
    }

    private func pluginIcon(_ session: ExtensionPromptSession) -> ExtensionIcon {
        center.plugins.first { $0.id == session.pluginID }?.manifest.icon ?? .fallback
    }

    private func pluginDirectory(_ session: ExtensionPromptSession) -> URL? {
        center.plugins.first { $0.id == session.pluginID }?.directory
    }

    private func dependencyRows(_ issues: [ExtensionDependencyIssue]) -> [ExtensionDependencyRowModel] {
        issues.map { issue in
            let presented = dependencyPresentation(issue)
            let enabled: Bool = if case .enable(let id) = issue.remedy {
                center.plugins.first { $0.id == id }?.enabled ?? false
            } else {
                false
            }
            return ExtensionDependencyRowModel(
                issue: issue,
                icon: presented.icon,
                directory: presented.directory,
                enabled: enabled
            )
        }
    }

    private func dependencyPresentation(_ issue: ExtensionDependencyIssue) -> (icon: ExtensionIcon, directory: URL?) {
        switch issue.remedy {
        case .enable(let id):
            let plugin = center.plugins.first { $0.id == id }
            return (plugin?.manifest.icon ?? .fallback, plugin?.directory)
        case .install(let id):
            let entry = ExtensionCatalogClient.shared.entries.first { $0.id == id }
            return (entry?.icon ?? .fallback, ExtensionCatalogClient.shared.localPackageURL(id: id))
        case .unavailable:
            return (.fallback, nil)
        }
    }

    private func formCard(_ session: ExtensionPromptSession) -> some View {
        card(
            height: ExtensionBubbleMetrics.promptCardHeight(kinds: session.groupKinds),
            arrow: showsArrow
        ) {
            ExtensionPromptForm(
                session: session,
                directory: center.plugins.first { $0.id == session.pluginID }?.directory,
                icon: center.plugins.first { $0.id == session.pluginID }?.manifest.icon ?? .fallback,
                onConfirm: { center.confirmPrompt() },
                onClose: { center.cancelSession() }
            )
        }
    }

    private func card<Content: View>(
        height: CGFloat,
        padding: CGFloat = ExtensionBubbleMetrics.formPadding,
        arrow: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let edge = placement.arrowEdge
        let extent = arrow ? ExtensionBubbleMetrics.arrowExtent : 0
        let shape = PopoverBubbleShape(
            arrowEdge: edge,
            cornerRadius: 16,
            arrowWidth: arrow ? ExtensionBubbleMetrics.arrowWidth : 0,
            arrowHeight: extent
        )
        let horizontal = edge == .leading || edge == .trailing
        let shapeWidth = ExtensionBubbleMetrics.cardWidth + (horizontal ? extent : 0)
        let shapeHeight = height + (horizontal ? 0 : extent)
        // The arrow hangs off the body. Align the shape so the body covers this
        // frame and the tip draws outside it, the way an absolute element would.
        let shapeAlignment: Alignment = switch edge {
        case .leading: .trailing
        case .trailing: .leading
        case .top: .bottom
        case .bottom: .top
        }
        return content()
            .padding(padding)
            .frame(width: ExtensionBubbleMetrics.cardWidth, height: height, alignment: .top)
            .background(alignment: shapeAlignment) {
                StatusBubble.chromeMaterial(
                    shape,
                    style: AppSettings.shared.bubbleGlassStyle,
                    tint: AppSettings.shared.bubbleGlassTint,
                    suppressGlass: suppressBubbleGlass
                )
                .frame(width: shapeWidth, height: shapeHeight)
            }
            // Under the glass, inside this card. Omitted when a bubble sits
            // below, so the stack gap stays 4pt.
            .padding(.bottom, bottomShadowRoom)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(AiboPanelSpace.name))
            } action: { frame in
                AiboPanelController.shared.noteExtensionCardFrame(frame)
            }
    }
}

/// Prompt plates drawn without `Form`: header, one plate per group, then the actions.
private struct ExtensionPromptForm: View {
    var session: ExtensionPromptSession
    var directory: URL?
    var icon: ExtensionIcon = .fallback
    var onConfirm: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.groupSpacing) {
            ExtensionPluginHeader(name: session.pluginName, directory: directory, icon: icon)
            ForEach(session.groups) { group in
                ExtensionPromptPlate(controls: group.controls, session: session)
            }
            ExtensionPromptActions(session: session, onConfirm: onConfirm, onClose: onClose)
        }
    }
}

private struct ExtensionPromptActions: View {
    var session: ExtensionPromptSession
    var onConfirm: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Confirm"), action: onConfirm)
                .buttonStyle(.borderedProminent)
                .disabled(!session.canConfirm)
            Button(String(localized: "Close"), action: onClose)
                .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
        .frame(maxWidth: .infinity, minHeight: ExtensionBubbleMetrics.buttonRowHeight, maxHeight: ExtensionBubbleMetrics.buttonRowHeight, alignment: .leading)
    }
}

private struct ExtensionPromptPlate: View {
    var controls: [ExtensionPromptControl]
    var session: ExtensionPromptSession

    var body: some View {
        VStack(spacing: 0) {
            ForEach(controls) { control in
                VStack(spacing: 0) {
                    row(control)
                    if control.id != controls.last?.id {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: ExtensionBubbleMetrics.separatorHeight)
                            .padding(.horizontal, ExtensionBubbleMetrics.rowPadding)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.groupCornerRadius, style: .continuous)
                .fill(Color(nsColor: .tertiarySystemFill))
        }
    }

    @ViewBuilder
    private func row(_ control: ExtensionPromptControl) -> some View {
        switch control.kind {
        case .text:
            ExtensionPromptTextRow(
                title: control.title,
                showsWell: controls.count == 1,
                text: stringBinding(control.key, multiline: true)
            )
        case .line:
            ExtensionPromptLineRow(
                title: control.title,
                showsWell: controls.count == 1,
                text: stringBinding(control.key, multiline: false)
            )
        case .menu:
            ExtensionPromptMenuRow(title: control.title, choices: control.choices, selection: stringBinding(control.key))
        case .radio:
            ExtensionPromptRadioRow(title: control.title, choices: control.choices, selection: stringBinding(control.key))
        case .toggle:
            ExtensionPromptSwitchRow(title: control.title, isOn: toggleBinding(control.key))
        case .image:
            ExtensionPromptImageRow(title: control.title, path: stringBinding(control.key)) {
                session.chooseImage(for: control.key)
            }
        }
    }

    private func stringBinding(_ key: String, multiline: Bool? = nil) -> Binding<String> {
        Binding(
            get: { session.values[key] ?? "" },
            set: { newValue in
                let next = multiline.map { ExtensionPromptText.normalized(newValue, multiline: $0) } ?? newValue
                guard session.values[key] != next else { return }
                session.values[key] = next
            }
        )
    }

    private func toggleBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { session.toggles[key] ?? false },
            set: { session.toggles[key] = $0 }
        )
    }
}

private struct ExtensionPromptLabeledRow<Control: View>: View {
    var title: String
    var height: CGFloat = ExtensionBubbleMetrics.rowHeight
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, ExtensionBubbleMetrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
}

/// Plugin name row. Draws the author-declared icon, or the default tile.
private struct ExtensionPluginHeader: View {
    var name: String
    var directory: URL?
    var icon: ExtensionIcon = .fallback

    var body: some View {
        HStack(spacing: 6) {
            ExtensionIconBadge(
                icon: icon,
                directory: directory,
                side: ExtensionBubbleMetrics.pluginIconSize,
                cornerRadius: ExtensionBubbleMetrics.pluginIconCornerRadius,
                symbolPointSize: 14
            )
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(height: ExtensionBubbleMetrics.pluginHeaderHeight, alignment: .leading)
    }
}

private struct ExtensionPromptTextRow: View {
    var title: String
    /// Alone on its plate the well marks the field. Grouped with other rows, the plate fill is enough.
    var showsWell: Bool
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.multilineSpacing) {
            Text(title)
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: ExtensionBubbleMetrics.labelLineHeight, maxHeight: ExtensionBubbleMetrics.labelLineHeight, alignment: .leading)
            ExtensionPromptField(text: $text, multiline: true, inset: showsWell)
                .padding(showsWell ? 6 : 0)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ExtensionBubbleMetrics.multilineWellHeight,
                    maxHeight: ExtensionBubbleMetrics.multilineWellHeight,
                    alignment: .topLeading
                )
                .background { well }
                .accessibilityLabel(title)
        }
        .padding(ExtensionBubbleMetrics.textGroupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var well: some View {
        if showsWell {
            RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                .fill(Color(nsColor: .secondarySystemFill))
        }
    }
}

private struct ExtensionPromptLineRow: View {
    var title: String
    /// Alone on its plate the well marks the field. Grouped with other rows, the plate fill is enough.
    var showsWell: Bool
    @Binding var text: String

    var body: some View {
        ExtensionPromptLabeledRow(title: title) {
            ExtensionPromptField(text: $text, multiline: false, inset: showsWell)
                .padding(.horizontal, showsWell ? 8 : 0)
                .frame(width: 132, height: 28)
                .background { well }
        }
    }

    @ViewBuilder
    private var well: some View {
        if showsWell {
            RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                .fill(Color(nsColor: .secondarySystemFill))
        }
    }
}

private struct ExtensionPromptMenuRow: View {
    var title: String
    var choices: [ExtensionChoiceOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Picker(selection: $selection) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.value)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ExtensionBubbleMetrics.rowPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: ExtensionBubbleMetrics.rowHeight,
            maxHeight: ExtensionBubbleMetrics.rowHeight
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct ExtensionPromptRadioRow: View {
    var title: String
    var choices: [ExtensionChoiceOption]
    @Binding var selection: String

    var body: some View {
        ExtensionPromptLabeledRow(title: title) {
            Picker(title, selection: $selection) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
            .fixedSize()
        }
    }
}

private struct ExtensionPromptSwitchRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        ExtensionPromptLabeledRow(title: title) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct ExtensionPromptImageRow: View {
    var title: String
    @Binding var path: String
    var onPick: () -> Void

    var body: some View {
        ExtensionPromptLabeledRow(title: title, height: ExtensionBubbleMetrics.imageRowHeight) {
            Button(action: onPick) {
                ZStack {
                    RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .secondarySystemFill))
                    if let image = NSImage(contentsOfFile: path), !path.isEmpty {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: ExtensionBubbleMetrics.imageTile, height: ExtensionBubbleMetrics.imageTile)
                .clipShape(RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        }
    }
}

#Preview("plugin prompt") {
    let session = ExtensionPromptSession(
        pluginID: "dev.aibo.translate",
        pluginName: "Translate",
        groups: [
            ExtensionPromptGroup(controls: [
                ExtensionPromptControl(key: "text", title: "Text", kind: .text, choices: []),
                ExtensionPromptControl(
                    key: "target",
                    title: "Target language",
                    kind: .menu,
                    choices: [
                        ExtensionChoiceOption(value: "zh-Hans", title: "简体中文"),
                        ExtensionChoiceOption(value: "en", title: "English"),
                        ExtensionChoiceOption(value: "ja", title: "日本語"),
                    ]
                ),
            ]),
        ],
        values: ["text": "", "target": "en"],
        toggles: [:],
        required: ["text"]
    )
    ExtensionPromptForm(session: session, directory: nil, onConfirm: {}, onClose: {})
        .padding(ExtensionBubbleMetrics.formPadding)
        .frame(
            width: ExtensionBubbleMetrics.cardWidth,
            height: ExtensionBubbleMetrics.promptCardHeight(kinds: session.groupKinds),
            alignment: .top
        )
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
}
