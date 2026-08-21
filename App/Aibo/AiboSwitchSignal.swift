import CoreGraphics
import Foundation

/// Broadcasts an aibo switch so every mounted preview can play the morph.
///
/// Desktop `AiboView` is often rebuilt when `select` resizes the panel, so a
/// child `onChange(of: record.id)` never sees the old id and the sprite just
/// jumps. Views consume `sequence` (including on first appear) if the event is
/// still fresh.
///
/// `canvasSize` is the union of both desktop sizes. Each artwork is drawn at
/// its own size, centered; extra area is transparent so the panel can grow
/// once up front instead of stretching one sprite then snapping at the end.
@MainActor
@Observable
final class AiboSwitchSignal {
    static let shared = AiboSwitchSignal()

    /// Ignore stale events when a settings pane appears long after a switch.
    static let freshness: TimeInterval = 1.5

    private(set) var sequence: UInt64 = 0
    private(set) var fromID: String = ""
    private(set) var toID: String = ""
    private(set) var issuedAt: Date = .distantPast
    private(set) var fromDesktopSize: CGSize = .zero
    private(set) var toDesktopSize: CGSize = .zero
    private(set) var canvasSize: CGSize = .zero
    private(set) var locksDesktopSize = false

    private init() {}

    static func enclosing(_ a: CGSize, _ b: CGSize) -> CGSize {
        CGSize(width: max(a.width, b.width), height: max(a.height, b.height))
    }

    func emit(
        from fromID: String,
        to toID: String,
        fromDesktopSize: CGSize,
        toDesktopSize: CGSize
    ) {
        guard fromID != toID else { return }
        sequence += 1
        self.fromID = fromID
        self.toID = toID
        self.fromDesktopSize = fromDesktopSize
        self.toDesktopSize = toDesktopSize
        canvasSize = Self.enclosing(fromDesktopSize, toDesktopSize)
        issuedAt = Date()
        locksDesktopSize = canvasSize.width > 1
            && canvasSize.height > 1
            && AiboPanelController.shared.isContentPresented
        if locksDesktopSize {
            AiboPanelController.shared.syncGeometryNow()
        }
    }

    func desktopMorphDidFinish() {
        guard locksDesktopSize else { return }
        locksDesktopSize = false
        AiboPanelController.shared.updateHitTestImage()
        AiboPanelController.shared.refreshContent()
    }

    var isFresh: Bool {
        Date().timeIntervalSince(issuedAt) < Self.freshness
    }
}
