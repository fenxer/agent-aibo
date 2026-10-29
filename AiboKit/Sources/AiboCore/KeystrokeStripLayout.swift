import Foundation

/// How a key group is drawn: cap size, wrap, and the on-screen maximum.
///
/// Up to 6 keys stay at 72. A longer row shrinks to 40 and wraps every 10.
/// Past 4 rows every cap shrinks to 24, and the strip stops at 10 rows.
public struct KeystrokeStripLayout: Equatable, Sendable {
    public static let regularSide = 72.0
    public static let compactSide = 40.0
    public static let denseSide = 24.0
    public static let spacing = 8.0
    public static let regularRowLimit = 6
    public static let keysPerWrappedRow = 10
    public static let compactRowLimit = 4
    public static let maxRows = 10
    public static let defaultLimit = 6
    public static var visualCap: Int { keysPerWrappedRow * maxRows }

    public var side: Double
    public var keysPerRow: Int
    public var rows: Int
    public var count: Int
    public var width: Double
    public var height: Double

    /// `0` means no numeric cap, still bounded by `visualCap`.
    public static func cap(limit: Int) -> Int {
        if limit <= 0 { return visualCap }
        return min(limit, visualCap)
    }

    public static func layout(count: Int) -> Self {
        let shown = min(max(count, 0), visualCap)
        if shown == 0 {
            return Self(
                side: regularSide,
                keysPerRow: 1,
                rows: 0,
                count: 0,
                width: 0,
                height: 0
            )
        }
        if shown <= regularRowLimit {
            return make(count: shown, side: regularSide, keysPerRow: shown)
        }
        let wrappedRows = (shown + keysPerWrappedRow - 1) / keysPerWrappedRow
        if wrappedRows <= compactRowLimit {
            return make(count: shown, side: compactSide, keysPerRow: keysPerWrappedRow)
        }
        return make(count: shown, side: denseSide, keysPerRow: keysPerWrappedRow)
    }

    private static func make(count: Int, side: Double, keysPerRow: Int) -> Self {
        let rows = max(1, (count + keysPerRow - 1) / keysPerRow)
        let longest = min(count, keysPerRow)
        let width = Double(longest) * side + Double(max(0, longest - 1)) * spacing
        let height = Double(rows) * side + Double(max(0, rows - 1)) * spacing
        return Self(
            side: side,
            keysPerRow: keysPerRow,
            rows: rows,
            count: count,
            width: width,
            height: height
        )
    }
}
