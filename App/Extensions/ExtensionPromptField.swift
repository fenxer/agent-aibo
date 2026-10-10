import AiboCore
import AppKit
import SwiftUI

/// SwiftUI frame of each prompt field, in the panel hosting view (top-left).
///
/// Beside a hook bubble the card is drawn outside the anchor view. AppKit
/// `hitTest` stops at that ancestor, so a click on the glyphs never reaches
/// the text view and the caret stays where the keyboard left it.
/// Main-thread only: AppKit hit testing and SwiftUI geometry both run there.
enum PromptFieldTracker {
    weak static var host: NSView?
    private static var tokens: [PromptFieldToken] = []

    static func register(_ token: PromptFieldToken) {
        guard tokens.contains(where: { $0 === token }) == false else { return }
        tokens.append(token)
    }

    static func unregister(_ token: PromptFieldToken) {
        tokens.removeAll { $0 === token }
    }

    static func frame(of textView: PromptTextView) -> CGRect? {
        tokens.first { $0.textView === textView }?.frame
    }

    static func textView(at point: NSPoint) -> PromptTextView? {
        for token in tokens.reversed() {
            guard token.frame.contains(point), let textView = token.textView, textView.window != nil else {
                continue
            }
            // A field in the detached window must not steal clicks aimed at the pet.
            if let host, textView.window !== host.window { continue }
            return textView
        }
        return nil
    }
}

final class PromptFieldToken {
    weak var textView: PromptTextView?
    var frame: CGRect = .null
}

/// Plain prompt field. TextKit 1 so a click can move the caret; paste is normalized
/// before it lands, including when the cleaned string matches what is already stored.
struct ExtensionPromptField: View {
    @Binding var text: String
    var multiline: Bool
    /// Inset inside a well. Off when the field shares a plate, so the text lines up with the label above.
    var inset: Bool = true
    @State private var token = PromptFieldToken()
    @Environment(\.extensionBubbleChrome) private var chrome

    var body: some View {
        ExtensionPromptFieldRepresentable(text: $text, multiline: multiline, inset: inset, token: token)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(AiboPanelSpace.name))
            } action: { frame in
                guard chrome == .anchored else {
                    token.frame = .null
                    PromptFieldTracker.unregister(token)
                    return
                }
                token.frame = frame
                PromptFieldTracker.register(token)
            }
            .onDisappear {
                PromptFieldTracker.unregister(token)
            }
    }
}

private struct ExtensionPromptFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var multiline: Bool
    var inset: Bool
    var token: PromptFieldToken

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, multiline: multiline, token: token)
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
        token.textView = textView

        scroll.documentView = textView
        context.coordinator.textView = textView
        PromptFieldTracker.register(token)
        return scroll
    }

    static func dismantleNSView(_ nsView: PromptScrollView, coordinator: Coordinator) {
        PromptFieldTracker.unregister(coordinator.token)
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
        var token: PromptFieldToken
        weak var textView: PromptTextView?
        private var applying = false

        init(text: Binding<String>, multiline: Bool, token: PromptFieldToken) {
            self.text = text
            self.multiline = multiline
            self.token = token
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

/// Click places the caret from the field's SwiftUI frame. `super.mouseDown` does
/// not: the hook bubble's tap gesture cancels that selection and leaves the
/// insertion point at the end. Arrow keys still work because they never enter
/// that gesture.
final class PromptTextView: NSTextView {
    /// Host-point index where the current click began. Drag extends from here.
    var clickAnchor: Int?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        (window as? AiboPanel)?.makeKey()
        window?.makeFirstResponder(self)
        guard let host = PromptFieldTracker.host else { return }
        beginClick(atHostPoint: host.convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let host = PromptFieldTracker.host else { return }
        extendClick(toHostPoint: host.convert(event.locationInWindow, from: nil))
    }

    func beginClick(atHostPoint point: NSPoint, clickCount: Int) {
        let index = characterIndex(atHostPoint: point)
        clickAnchor = index
        if clickCount >= 2 {
            let granularity: NSSelectionGranularity = clickCount >= 3 ? .selectByParagraph : .selectByWord
            let proposed = NSRange(location: min(index, (string as NSString).length), length: 0)
            let range = selectionRange(forProposedRange: proposed, granularity: granularity)
            setSelectedRange(range)
            clickAnchor = range.location
        } else {
            setSelectedRange(NSRange(location: index, length: 0))
        }
        scrollRangeToVisible(selectedRange())
    }

    func extendClick(toHostPoint point: NSPoint) {
        let index = characterIndex(atHostPoint: point)
        let anchor = clickAnchor ?? index
        let location = min(anchor, index)
        setSelectedRange(NSRange(location: location, length: abs(index - anchor)))
        scrollRangeToVisible(selectedRange())
    }

    func characterIndex(atHostPoint point: NSPoint) -> Int {
        let length = (string as NSString).length
        guard let layoutManager, let container = textContainer else { return length }
        layoutManager.ensureLayout(for: container)
        guard var local = pointInTextView(fromHostPoint: point) else { return length }
        let origin = textContainerOrigin
        local.x -= origin.x
        local.y -= origin.y
        // A click in the empty part of a tall well is below the glyphs. TextKit
        // then reports the end of the string, so the caret never enters the text.
        // Keep the horizontal position and pin Y to the nearest laid-out line.
        let used = layoutManager.usedRect(for: container)
        if used.width > 1, used.height > 1, local.x >= used.minX, local.x <= used.maxX + 1 {
            if local.y < used.minY { local.y = used.minY + 0.5 }
            if local.y > used.maxY { local.y = used.maxY - 0.5 }
        }
        var fraction: CGFloat = 0
        var index = layoutManager.characterIndex(
            for: local,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        if index < 0 || index > length {
            index = length
        }
        if fraction >= 0.5, index < length {
            index += 1
        }
        return index
    }

    /// Point in this text view. Prefer AppKit's own conversion; the SwiftUI
    /// frame is the fallback when an ancestor clipped the view out of hit testing
    /// and the view's frame no longer matches where the glyphs were drawn.
    private func pointInTextView(fromHostPoint point: NSPoint) -> NSPoint? {
        if let host = PromptFieldTracker.host {
            let converted = host.convert(point, to: self)
            if bounds.insetBy(dx: -2, dy: -2).contains(converted) {
                return converted
            }
        }
        guard let tokenFrame = frameInPanel, tokenFrame.width > 1, tokenFrame.height > 1 else { return nil }
        let clip = enclosingScrollView?.contentView.bounds.origin ?? .zero
        return NSPoint(
            x: min(max(point.x, tokenFrame.minX), tokenFrame.maxX - 1) - tokenFrame.minX + clip.x,
            y: min(max(point.y, tokenFrame.minY), tokenFrame.maxY - 1) - tokenFrame.minY + clip.y
        )
    }

    private var frameInPanel: CGRect? {
        PromptFieldTracker.frame(of: self)
    }
}
