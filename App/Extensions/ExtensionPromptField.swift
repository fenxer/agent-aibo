import AiboCore
import AppKit
import SwiftUI

/// Plain prompt field. TextKit 1 so a click can move the caret; paste is normalized
/// before it lands, including when the cleaned string matches what is already stored.
struct ExtensionPromptField: View {
    @Binding var text: String
    var multiline: Bool
    /// Inset inside a well. Off when the field shares a plate, so the text lines up with the label above.
    var inset: Bool = true

    var body: some View {
        ExtensionPromptFieldRepresentable(text: $text, multiline: multiline, inset: inset)
    }
}

private struct ExtensionPromptFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var multiline: Bool
    var inset: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, multiline: multiline)
    }

    func makeNSView(context: Context) -> PromptScrollView {
        let scroll = PromptScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.multiline = multiline
        scroll.inset = inset

        let textView = PromptTextView(usingTextLayoutManager: false)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: ExtensionBubbleMetrics.fieldFontSize)
        textView.textColor = .labelColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = multiline
        textView.isHorizontallyResizable = !multiline
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: PromptScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.multiline = multiline
        scroll.multiline = multiline
        scroll.inset = inset
        scroll.horizontalScrollElasticity = multiline ? .none : .allowed
        scroll.verticalScrollElasticity = multiline ? .allowed : .none
        guard let textView = context.coordinator.textView else { return }
        textView.font = .systemFont(ofSize: ExtensionBubbleMetrics.fieldFontSize)
        if textView.string != text {
            context.coordinator.replaceText(text, in: textView)
        }
        scroll.layoutText()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var multiline: Bool
        weak var textView: PromptTextView?
        private var applying = false

        init(text: Binding<String>, multiline: Bool) {
            self.text = text
            self.multiline = multiline
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !applying, let replacementString else { return true }
            let cleaned = ExtensionPromptText.normalized(replacementString, multiline: multiline)
            guard cleaned != replacementString else { return true }
            let current = textView.string as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= current.length else { return true }
            let updated = current.replacingCharacters(in: range, with: cleaned)
            replaceText(updated, in: textView, caret: range.location + (cleaned as NSString).length)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard !applying, let textView else { return }
            let cleaned = ExtensionPromptText.normalized(textView.string, multiline: multiline)
            if cleaned != textView.string {
                replaceText(cleaned, in: textView, caret: textView.selectedRange().location)
                return
            }
            publish(textView.string)
        }

        fileprivate func replaceText(_ updated: String, in textView: NSTextView, caret: Int? = nil) {
            applying = true
            let caret = caret ?? textView.selectedRange().location
            textView.string = updated
            let length = (updated as NSString).length
            textView.setSelectedRange(NSRange(location: min(max(0, caret), length), length: 0))
            applying = false
            textView.scrollRangeToVisible(textView.selectedRange())
            publish(updated)
        }

        private func publish(_ value: String) {
            guard text.wrappedValue != value else { return }
            text.wrappedValue = value
        }
    }
}

final class PromptScrollView: NSScrollView {
    var multiline = true
    /// Horizontal room inside a well. A field that shares its plate has none, so the glyphs meet the label.
    var inset = true

    private var isLayingOutText = false

    override func layout() {
        super.layout()
        layoutText()
    }

    func layoutText() {
        guard isLayingOutText == false, let textView = documentView as? NSTextView else { return }
        isLayingOutText = true
        defer { isLayingOutText = false }
        let width = max(1, contentView.bounds.width)
        let height = max(1, contentView.bounds.height)
        textView.textContainer?.lineFragmentPadding = (multiline && inset) ? 5 : 0
        if multiline {
            textView.textContainer?.maximumNumberOfLines = 0
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainerInset = .zero
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            let used = textView.textContainer.flatMap { textView.layoutManager?.usedRect(for: $0).height } ?? height
            textView.frame = NSRect(x: 0, y: 0, width: width, height: max(height, ceil(used)))
        } else {
            textView.textContainer?.maximumNumberOfLines = 1
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: height
            )
            textView.isHorizontallyResizable = true
            textView.isVerticallyResizable = false
            let font = textView.font ?? .systemFont(ofSize: ExtensionBubbleMetrics.fieldFontSize)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let inset = max(0, (height - lineHeight) / 2)
            textView.textContainerInset = NSSize(width: 0, height: inset)
            let usedWidth = textView.textContainer.flatMap { textView.layoutManager?.usedRect(for: $0).width } ?? width
            textView.frame = NSRect(x: 0, y: 0, width: max(width, usedWidth + 8), height: height)
        }
    }
}

final class PromptTextView: NSTextView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
