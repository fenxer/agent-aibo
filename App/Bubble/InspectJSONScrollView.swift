import AppKit
import SwiftUI

/// AppKit scroll view so hook JSON can scroll inside a parent that uses
/// `fixedSize(vertical: true)` (SwiftUI `ScrollView` expands to the full text).
///
/// The parent gives this view a concrete height. `sizeThatFits` reports the
/// capped content height and ignores a zero proposal so the block cannot
/// collapse to an empty slot.
struct InspectJSONScrollView: NSViewRepresentable {
    var text: String
    var prefersLightInk: Bool
    var maxHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true

        let textView = InspectJSONTextView(usingTextLayoutManager: false)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(
            ofSize: HookInspectLayout.jsonFontSize,
            weight: .regular
        )
        applyInk(prefersLightInk, to: textView)
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        applyInk(prefersLightInk, to: textView)
        layoutTextView(textView, in: scroll)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSScrollView,
        context: Context
    ) -> CGSize? {
        let width = max(1, proposal.width ?? 280)
        let used = min(maxHeight, contentHeight(width: width))
        if let textView = context.coordinator.textView ?? nsView.documentView as? NSTextView {
            layoutTextView(textView, in: nsView, width: width)
        }
        return CGSize(width: width, height: used)
    }

    private func contentHeight(width: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(
            ofSize: HookInspectLayout.jsonFontSize,
            weight: .regular
        )
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(14, ceil(rect.height))
    }

    private func layoutTextView(
        _ textView: NSTextView,
        in scroll: NSScrollView,
        width: CGFloat? = nil
    ) {
        let resolvedWidth = width ?? max(1, scroll.contentView.bounds.width)
        guard resolvedWidth > 1 else { return }
        textView.textContainer?.containerSize = NSSize(
            width: resolvedWidth,
            height: .greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        let used = contentHeight(width: resolvedWidth)
        let height = max(used, scroll.contentView.bounds.height)
        textView.frame = NSRect(x: 0, y: 0, width: resolvedWidth, height: height)
    }

    private func applyInk(_ prefersLight: Bool, to textView: NSTextView) {
        textView.textColor = prefersLight ? .white : .black
    }

    final class Coordinator {
        var textView: NSTextView?
    }
}

/// Don't steal first responder on a non-activating panel.
private final class InspectJSONTextView: NSTextView {
    override var acceptsFirstResponder: Bool { false }
}
