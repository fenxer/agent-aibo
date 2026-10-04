import AiboCore
import AppKit
import SwiftUI

enum ExtensionBubbleMetrics {
    static let cardWidth: CGFloat = 300
    static let formSpacing: CGFloat = 8
    static let formLabelHeight: CGFloat = 16
    static let formFieldHeight: CGFloat = 58
    static let formControlHeight: CGFloat = 32
    static let formPadding: CGFloat = 12
    static let statusSpacing: CGFloat = 10
    /// Result / error copy scrolls inside this, so a long translation cannot stretch the card.
    static let resultTextMaxHeight: CGFloat = 140

    /// Label, field, language menu, and the confirm/close row. No slack under the buttons.
    static var formHeight: CGFloat {
        formPadding * 2
            + formLabelHeight + formSpacing
            + formFieldHeight + formSpacing
            + formLabelHeight + formSpacing
            + formControlHeight + formSpacing
            + formControlHeight
    }

    static func statusHeight(text: String) -> CGFloat {
        formPadding * 2 + textBlockHeight(text) + statusSpacing + formControlHeight
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
        .frame(width: 320, alignment: frameAlignment)
    }

    private var frameAlignment: Alignment {
        switch placement {
        case .left: .trailing
        case .right: .leading
        case .top, .bottom: .center
        }
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
        card(height: ExtensionBubbleMetrics.formHeight, arrow: showsArrow) {
            VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.formSpacing) {
                Text(session.textTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: ExtensionBubbleMetrics.formLabelHeight, alignment: .leading)
                TextField(session.textTitle, text: textBinding(session), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: ExtensionBubbleMetrics.formFieldHeight, alignment: .top)
                Text(session.choiceTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: ExtensionBubbleMetrics.formLabelHeight, alignment: .leading)
                Picker(session.choiceTitle, selection: targetBinding(session)) {
                    ForEach(session.choices) { choice in
                        Text(choice.title).tag(choice.value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: ExtensionBubbleMetrics.formControlHeight, alignment: .leading)
                HStack(spacing: 8) {
                    Button(String(localized: "Confirm")) {
                        center.confirmPrompt()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(String(localized: "Close")) {
                        center.cancelSession()
                    }
                }
                .frame(height: ExtensionBubbleMetrics.formControlHeight, alignment: .leading)
            }
        }
    }

    private func statusCard(text: String, copyText: String?, showsClose: Bool, arrow: Bool) -> some View {
        let textHeight = ExtensionBubbleMetrics.textBlockHeight(text)
        return card(height: ExtensionBubbleMetrics.statusHeight(text: text), arrow: arrow) {
            VStack(alignment: .leading, spacing: ExtensionBubbleMetrics.statusSpacing) {
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
    }

    private func textBinding(_ session: ExtensionPromptSession) -> Binding<String> {
        Binding(get: { session.text }, set: { session.text = $0 })
    }

    private func targetBinding(_ session: ExtensionPromptSession) -> Binding<String> {
        Binding(get: { session.target }, set: { session.target = $0 })
    }

    private func card<Content: View>(
        height: CGFloat,
        arrow: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = PopoverBubbleShape(
            arrowEdge: placement.arrowEdge,
            cornerRadius: 16,
            arrowWidth: arrow ? 10 : 0,
            arrowHeight: arrow ? 6 : 0
        )
        return content()
            .padding(ExtensionBubbleMetrics.formPadding)
            .frame(width: ExtensionBubbleMetrics.cardWidth, height: height, alignment: .topLeading)
            .background {
                StatusBubble.chromeMaterial(
                    shape,
                    style: AppSettings.shared.bubbleGlassStyle,
                    tint: AppSettings.shared.bubbleGlassTint,
                    suppressGlass: false
                )
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(AiboPanelSpace.name))
            } action: { frame in
                AiboPanelController.shared.noteExtensionCardFrame(frame)
            }
    }
}
