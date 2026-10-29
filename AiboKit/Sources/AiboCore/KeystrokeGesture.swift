import Foundation

/// One keycap in the group currently shown beside the aibo.
public struct KeystrokePress: Identifiable, Equatable, Sendable {
    /// Unique per appearance, so the same letter can show twice in one group.
    public var id: String
    /// Physical key. Repeats while it is still held do not add another cap.
    public var physicalID: String
    public var isModifier: Bool
    public var label: String
    public var symbolName: String?
    /// Place in the group when this cap was added. Drives the staggered appear.
    public var staggerIndex: Int

    public init(
        id: String,
        physicalID: String? = nil,
        isModifier: Bool,
        label: String,
        symbolName: String?,
        staggerIndex: Int = 0
    ) {
        self.id = id
        self.physicalID = physicalID ?? id
        self.isModifier = isModifier
        self.label = label
        self.symbolName = symbolName
        self.staggerIndex = staggerIndex
    }
}

/// One on-screen group of keycaps.
///
/// A press joins the current group when it follows the previous press within
/// `groupGap`. A longer gap replaces the group. `limit` is the most caps kept;
/// `0` keeps filling until `KeystrokeStripLayout.visualCap`. A further press
/// drops the oldest cap.
public struct KeystrokeGesture: Equatable, Sendable {
    /// Seconds. Presses farther apart than this start a new group.
    public static let groupGap: TimeInterval = 0.5

    public private(set) var displayed: [KeystrokePress] = []
    public var hasHeldKeys: Bool { held.isEmpty == false }
    private var held: [String] = []
    private var lastPressAt: TimeInterval?
    private var serial = 0

    public init() {}

    public mutating func press(_ key: KeystrokePress, at time: TimeInterval, limit: Int = KeystrokeStripLayout.defaultLimit) {
        if let lastPressAt, time - lastPressAt > Self.groupGap {
            displayed = []
        }
        lastPressAt = time
        guard held.contains(key.physicalID) == false else { return }
        held.append(key.physicalID)
        var shown = key
        shown.id = "\(key.physicalID)#\(serial)"
        serial += 1
        shown.staggerIndex = displayed.count
        displayed.append(shown)
        trim(to: limit)
    }

    /// Drops the oldest caps when the setting shrinks below what is on screen.
    public mutating func clamp(to limit: Int) {
        trim(to: limit)
    }

    private mutating func trim(to limit: Int) {
        let cap = KeystrokeStripLayout.cap(limit: limit)
        let extra = displayed.count - cap
        if extra > 0 {
            displayed.removeFirst(extra)
        }
    }

    /// `true` when nothing is physically held. Caps stay in `displayed` until
    /// `clear()`, so the caller can linger the group.
    public mutating func release(id: String) -> Bool {
        guard let index = held.firstIndex(of: id) else { return false }
        held.remove(at: index)
        return held.isEmpty
    }

    public mutating func clear() {
        displayed = []
        held = []
        lastPressAt = nil
    }
}
