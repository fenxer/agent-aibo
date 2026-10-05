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
        case .running:
            statusCard(
                text: String(localized: "Working…"),
                copyText: nil,
                showsClose: true,
                arrow: showsArrow
            )
        case .result(let summary, let copyText):
            statusCard(text: summary, copyText: copyText, showsClose: true, arrow: showsArrow)
        case .failed(let message):
            statusCard(text: message, copyText: nil, showsClose: true, arrow: showsArrow)
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
                onConfirm: { center.confirmPrompt() },
                onClose: { center.cancelSession() }
            )
        }
    }

    private func statusCard(text: String, copyText: String?, showsClose: Bool, arrow: Bool) -> some View {
        card(height: ExtensionBubbleMetrics.statusCardHeight(text: text), arrow: arrow) {
            VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.pluginHeaderSpacing) {
                if let session {
                    pluginHeader(session)
                }
                statusBody(text: text, copyText: copyText, showsClose: showsClose)
            }
        }
    }

    private func statusBody(text: String, copyText: String?, showsClose: Bool) -> some View {
        let textHeight = ExtensionBubbleMetrics.textBlockHeight(text)
        return VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.statusSpacing) {
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: textHeight)
            HStack(spacing: 8) {
                if copyText != nil {
                    Button(String(localized: "Copy")) {
                        center.copyResult()
                    }
                }
                if showsClose {
                    Button(String(localized: "Close")) {
                        center.cancelSession()
                    }
                }
            }
            .frame(height: ExtensionBubbleMetrics.formControlHeight, alignment: .leading)
        }
    }

    private func pluginHeader(_ session: ExtensionPromptSession) -> some View {
        ExtensionPluginHeader(
            name: session.pluginName,
            directory: center.plugins.first { $0.id == session.pluginID }?.directory
        )
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
    var onConfirm: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.groupSpacing) {
            ExtensionPluginHeader(name: session.pluginName, directory: directory)
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
            ExtensionPromptTextRow(title: control.title, text: stringBinding(control.key))
        case .line:
            ExtensionPromptLineRow(title: control.title, text: stringBinding(control.key))
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

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { session.values[key] ?? "" },
            set: { session.values[key] = $0 }
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

/// Plugin name row. Uses `icon.png` from the plugin folder when there is one.
private struct ExtensionPluginHeader: View {
    var name: String
    var directory: URL?
    @Environment(\.colorScheme) private var colorScheme
    @State private var iconImage: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            icon
                .accessibilityHidden(true)
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(height: ExtensionBubbleMetrics.pluginHeaderHeight, alignment: .leading)
        .onAppear(perform: loadIcon)
        .onChange(of: directory) { _, _ in
            loadIcon()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: ExtensionBubbleMetrics.pluginIconSize, height: ExtensionBubbleMetrics.pluginIconSize)
                .clipShape(RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.pluginIconCornerRadius, style: .continuous))
        } else {
            let tile = colorScheme == .dark ? Color.white : Color.black
            let glyph = colorScheme == .dark ? Color.black : Color.white
            // SF Symbol layout rects sit below the ink. Draw the ink centered
            // in the tile so the baseline inset does not shift the glyph.
            Image(nsImage: Self.centeredSymbol)
                .renderingMode(.template)
                .foregroundStyle(glyph)
                .frame(width: ExtensionBubbleMetrics.pluginIconSize, height: ExtensionBubbleMetrics.pluginIconSize)
                .background(tile, in: RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.pluginIconCornerRadius, style: .continuous))
        }
    }

    private static let centeredSymbol: NSImage = {
        let side = ExtensionBubbleMetrics.pluginIconSize
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "square.text.square.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }
        let canvas = NSImage(size: NSSize(width: side, height: side))
        canvas.isTemplate = true
        canvas.lockFocus()
        let ink = symbol.alignmentRect
        symbol.draw(
            in: NSRect(
                x: (side - ink.width) / 2 - ink.origin.x,
                y: (side - ink.height) / 2 - ink.origin.y,
                width: symbol.size.width,
                height: symbol.size.height
            ),
            from: NSRect(origin: .zero, size: symbol.size),
            operation: .sourceOver,
            fraction: 1
        )
        canvas.unlockFocus()
        return canvas
    }()

    private func loadIcon() {
        guard let directory else {
            iconImage = nil
            return
        }
        iconImage = NSImage(contentsOf: directory.appendingPathComponent("icon.png"))
    }
}

private struct ExtensionPromptTextRow: View {
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.multilineSpacing) {
            Text(title)
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: ExtensionBubbleMetrics.labelLineHeight, maxHeight: ExtensionBubbleMetrics.labelLineHeight, alignment: .leading)
            TextEditor(text: $text)
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .multilineTextAlignment(.leading)
                .padding(6)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ExtensionBubbleMetrics.multilineWellHeight,
                    maxHeight: ExtensionBubbleMetrics.multilineWellHeight,
                    alignment: .topLeading
                )
                .background {
                    RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .secondarySystemFill))
                }
                .accessibilityLabel(title)
        }
        .padding(ExtensionBubbleMetrics.textGroupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExtensionPromptLineRow: View {
    var title: String
    @Binding var text: String

    var body: some View {
        ExtensionPromptLabeledRow(title: title) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: ExtensionBubbleMetrics.fieldFontSize))
                .padding(.horizontal, 8)
                .frame(width: 132, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: ExtensionBubbleMetrics.inputCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .secondarySystemFill))
                }
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
