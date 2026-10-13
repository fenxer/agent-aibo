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

    /// Detached window cannot shrink below the card width or a header-plus-actions stack.
    static let windowMinimumSize = NSSize(width: cardWidth, height: 160)
    /// Floor for a prompt text well once the window is shorter than the bubble.
    static let windowMinTextWell: CGFloat = 64
    /// Pop-out / pin hit target. Stays in the header row, which is already this tall.
    static let cornerButtonSide: CGFloat = 24
    /// Space between the zoom button and the plugin icon in the detached window.
    static let windowControlGap: CGFloat = 12
    /// Note-style title band. Traffic lights are centered in this, not in AppKit's shorter bar.
    static let windowHeaderBand: CGFloat = 52
    /// Window content sits this much closer to the title band than the bubble's stack spacing.
    static let windowHeaderContentTrim: CGFloat = 12
    /// Lights sit further in than AppKit's default so they clear the window corner.
    static let windowTrafficLightInset: CGFloat = 20
    /// Trailing margin of the glass control capsule, matching a note window's action group.
    static let windowHeaderTrailing: CGFloat = 8
    static let windowGlassPadding: CGFloat = 4
    /// Gap between the scene-marker capsule and the pin capsule.
    static let windowGlassButtonSpacing: CGFloat = 8
    /// Note panel corner. The window background is clear, so this shape is the glass edge.
    static let windowCornerRadius: CGFloat = 26

    static func controlHeight(_ kind: ExtensionPromptControl.Kind) -> CGFloat {
        controlHeight(kind, textWell: multilineWellHeight)
    }

    static func controlHeight(_ kind: ExtensionPromptControl.Kind, textWell: CGFloat) -> CGFloat {
        switch kind {
        case .text:
            textGroupPadding * 2 + labelLineHeight + multilineSpacing + textWell
        case .image: imageRowHeight
        default: rowHeight
        }
    }

    static func groupHeight(kinds: [ExtensionPromptControl.Kind]) -> CGFloat {
        groupHeight(kinds: kinds, textWell: multilineWellHeight)
    }

    static func groupHeight(kinds: [ExtensionPromptControl.Kind], textWell: CGFloat) -> CGFloat {
        let rows = kinds.reduce(CGFloat(0)) { $0 + controlHeight($1, textWell: textWell) }
        return rows + CGFloat(max(0, kinds.count - 1)) * separatorHeight
    }

    /// Plates only, without the header and confirm row.
    static func promptGroupsHeight(
        kinds: [[ExtensionPromptControl.Kind]],
        textWell: CGFloat
    ) -> CGFloat {
        let stacks = kinds.map { groupHeight(kinds: $0, textWell: textWell) }
        return stacks.reduce(0, +) + CGFloat(max(0, kinds.count - 1)) * groupSpacing
    }

    /// Share leftover window height across multiline wells. Short windows keep the floor.
    static func windowTextWellHeight(
        kinds: [[ExtensionPromptControl.Kind]],
        groupsAreaHeight: CGFloat
    ) -> CGFloat {
        let textCount = kinds.flatMap { $0 }.filter { $0 == .text }.count
        guard textCount > 0 else { return multilineWellHeight }
        let base = promptGroupsHeight(kinds: kinds, textWell: windowMinTextWell)
        let extra = groupsAreaHeight - base
        guard extra > 0 else { return windowMinTextWell }
        return windowMinTextWell + extra / CGFloat(textCount)
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

    static let fileChoiceSubtitleHeight: CGFloat = 16

    static func fileChoiceCardHeight(count: Int) -> CGFloat {
        let rows = CGFloat(max(count, 1)) * dependencyRowHeight
            + CGFloat(max(0, count - 1)) * dependencyRowSpacing
        return formPadding * 2
            + pluginHeaderHeight
            + pluginHeaderSpacing
            + fileChoiceSubtitleHeight
            + pluginHeaderSpacing
            + rows
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
    @Environment(\.extensionBubbleChrome) private var chrome

    private var session: ExtensionPromptSession? { center.session }

    var body: some View {
        if chrome == .window {
            windowBody
        } else {
            anchoredBody
        }
    }

    private var anchoredBody: some View {
        let alignment: HorizontalAlignment = switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
        return VStack(alignment: alignment, spacing: 4) {
            if let fileChoice = center.fileChoice {
                fileChoiceCard(fileChoice)
            } else if let session {
                cards(session: session)
            }
        }
        // No arrow on this card: keep the same pet-side slot the bubble below
        // uses for its triangle, so the two bodies line up.
        .padding(arrowSlotEdges, showsArrow ? 0 : ExtensionBubbleMetrics.arrowExtent)
        .frame(width: 320, alignment: frameAlignment)
        .buttonBorderShape(.capsule)
    }

    private var windowBody: some View {
        windowSession
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private var windowSession: some View {
        if let fileChoice = center.fileChoice {
            fileChoiceCard(fileChoice)
        } else if let session {
            cards(session: session)
        }
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

    private func fileChoiceCard(_ choice: ExtensionFileChoice) -> some View {
        card(
            height: ExtensionBubbleMetrics.fileChoiceCardHeight(count: choice.options.count),
            arrow: showsArrow
        ) {
            ExtensionFileChoiceCard(
                choice: choice,
                onChoose: { center.chooseDroppedPlugin(id: $0) },
                onClose: { center.cancelFileChoice() }
            )
        }
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

    @ViewBuilder
    private func card<Content: View>(
        height: CGFloat,
        padding: CGFloat = ExtensionBubbleMetrics.formPadding,
        arrow: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if chrome == .window {
            windowCard(padding: padding, content: content)
        } else {
            anchoredCard(height: height, padding: padding, arrow: arrow, content: content)
        }
    }

    /// Same card, filling the detached window. The header band draws its own insets.
    private func windowCard<Content: View>(
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, padding)
            .padding(.bottom, padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func anchoredCard<Content: View>(
        height: CGFloat,
        padding: CGFloat,
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

    @Environment(\.extensionBubbleChrome) private var chrome
    @State private var imagePasteMonitor: Any?

    var body: some View {
        pasteAware {
            if chrome == .window {
                windowBody
            } else {
                anchoredBody
            }
        }
    }

    /// `Command-V` fills the image field while this card is up. A focused text field keeps the keystroke.
    private func pasteAware<V: View>(@ViewBuilder content: () -> V) -> some View {
        content()
            .onAppear(perform: installImagePasteMonitor)
            .onDisappear(perform: removeImagePasteMonitor)
    }

    private func installImagePasteMonitor() {
        guard imagePasteMonitor == nil else { return }
        guard session.groups.flatMap(\.controls).contains(where: { $0.kind == .image }) else { return }
        let session = session
        let chrome = chrome
        imagePasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard ExtensionClipboardImage.isPasteShortcut(event, chrome: chrome) else { return event }
            return session.pasteImageFromClipboard() ? nil : event
        }
    }

    private func removeImagePasteMonitor() {
        if let imagePasteMonitor {
            NSEvent.removeMonitor(imagePasteMonitor)
        }
        imagePasteMonitor = nil
    }

    private var anchoredBody: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.groupSpacing) {
            header
            groups
            actions
        }
    }

    /// Header and actions stay put. Extra height goes to the text wells; a short window scrolls.
    private var windowBody: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.groupSpacing) {
            header
            GeometryReader { geo in
                promptGroups(in: geo.size)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, -ExtensionBubbleMetrics.windowHeaderContentTrim)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        ExtensionPluginHeader(name: session.pluginName, directory: directory, icon: icon)
    }

    private var groups: some View {
        ForEach(session.groups) { group in
            ExtensionPromptPlate(controls: group.controls, session: session)
        }
    }

    private var actions: some View {
        ExtensionPromptActions(session: session, onConfirm: onConfirm, onClose: onClose)
    }

    @ViewBuilder
    private func promptGroups(in size: CGSize) -> some View {
        let well = ExtensionBubbleMetrics.windowTextWellHeight(
            kinds: session.groupKinds,
            groupsAreaHeight: size.height
        ).rounded()
        let fits = ExtensionBubbleMetrics.promptGroupsHeight(
            kinds: session.groupKinds,
            textWell: well
        ) <= size.height + 1
        let stack = VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.groupSpacing) {
            groups
        }
        .environment(\.extensionTextWellHeight, well)
        .frame(maxWidth: .infinity, alignment: .top)

        if fits {
            stack.frame(width: size.width, height: size.height, alignment: .top)
        } else {
            ScrollView { stack }
                .frame(width: size.width, height: size.height)
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
        .controlSize(.extraLarge)
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
            } onPaste: {
                if session.pasteImage(for: control.key) == false {
                    NSSound.beep()
                }
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

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        HStack(spacing: 6) {
            pluginMark
            Spacer(minLength: 8)
            if chrome == .window {
                ExtensionBubbleCornerButton()
                    .modifier(ExtensionWindowGlassButton())
            } else {
                ExtensionBubbleCornerButton()
            }
        }
        .modifier(ExtensionWindowTitleBand(enabled: chrome == .window))
    }

    private var pluginMark: some View {
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
    }
}

private struct ExtensionPromptTextRow: View {
    var title: String
    /// Alone on its plate the well marks the field. Grouped with other rows, the plate fill is enough.
    var showsWell: Bool
    @Binding var text: String

    @Environment(\.extensionTextWellHeight) private var textWellOverride

    private var wellHeight: CGFloat {
        textWellOverride ?? ExtensionBubbleMetrics.multilineWellHeight
    }

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
                    minHeight: wellHeight,
                    maxHeight: wellHeight,
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

    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        ExtensionPromptLabeledRow(title: title) {
            field
        }
    }

    @ViewBuilder
    private var field: some View {
        let input = ExtensionPromptField(text: $text, multiline: false, inset: showsWell)
            .padding(.horizontal, showsWell ? 8 : 0)
        if chrome == .window {
            input
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                .background { well }
        } else {
            input
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
    var onPaste: () -> Void

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
            .contextMenu {
                Button("Paste", action: onPaste)
            }
        }
    }
}

private struct ExtensionFileChoiceCard: View {
    var choice: ExtensionFileChoice
    var onChoose: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
            HStack(spacing: 6) {
                Text("Choose an Extension")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            .frame(height: ExtensionBubbleMetrics.pluginHeaderHeight)
            Text(verbatim: choice.fileName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ExtensionBubbleMetrics.fileChoiceSubtitleHeight,
                    maxHeight: ExtensionBubbleMetrics.fileChoiceSubtitleHeight,
                    alignment: .leading
                )
            VStack(spacing: ExtensionBubbleMetrics.dependencyRowSpacing) {
                ForEach(choice.options) { option in
                    Button {
                        onChoose(option.id)
                    } label: {
                        ExtensionFileChoiceRow(option: option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ExtensionFileChoiceRow: View {
    var option: ExtensionDropOption

    var body: some View {
        HStack(spacing: 8) {
            ExtensionIconBadge(
                icon: option.icon,
                directory: option.directory,
                side: 28,
                cornerRadius: 6,
                symbolPointSize: 14
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !option.summary.isEmpty {
                    Text(option.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: ExtensionBubbleMetrics.dependencyRowHeight,
            maxHeight: ExtensionBubbleMetrics.dependencyRowHeight
        )
        .background {
            RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.groupCornerRadius, style: .continuous)
                .fill(Color(nsColor: .tertiarySystemFill))
        }
        .accessibilityElement(children: .combine)
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
