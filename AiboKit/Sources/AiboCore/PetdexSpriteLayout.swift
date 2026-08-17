import Foundation

/// Codex / Petdex atlas layout: 8 columns × 9 (v1) or 11 (v2) rows of 192×208 cells.
public enum PetdexSpriteState: String, Sendable, CaseIterable, Equatable, Hashable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    public var row: Int {
        switch self {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }

    public var frameCount: Int {
        switch self {
        case .idle: 6
        case .runningRight, .runningLeft, .failed: 8
        case .waving: 4
        case .jumping: 5
        case .waiting, .running, .review: 6
        }
    }

    /// Nominal loop duration in milliseconds (matches Petdex gallery metadata).
    public var durationMilliseconds: Int {
        switch self {
        case .idle: 1100
        case .runningRight, .runningLeft: 1060
        case .waving: 700
        case .jumping: 840
        case .failed: 1220
        case .waiting: 1010
        case .running: 820
        case .review: 1030
        }
    }
}

public struct PetdexSpriteLayout: Sendable, Equatable {
    public static let columns = 8
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let v1Rows = 9
    public static let v2Rows = 11

    public var pixelWidth: Int
    public var pixelHeight: Int
    public var rows: Int
    public var scale: Int

    public init?(pixelWidth: Int, pixelHeight: Int) {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        // Exact or integer scale of 1536×1872 (v1) or 1536×2288 (v2).
        let candidates: [(rows: Int, baseW: Int, baseH: Int)] = [
            (Self.v1Rows, Self.columns * Self.cellWidth, Self.v1Rows * Self.cellHeight),
            (Self.v2Rows, Self.columns * Self.cellWidth, Self.v2Rows * Self.cellHeight),
        ]
        for candidate in candidates {
            guard pixelWidth % candidate.baseW == 0 else { continue }
            let scale = pixelWidth / candidate.baseW
            guard scale >= 1, pixelHeight == candidate.baseH * scale else { continue }
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.rows = candidate.rows
            self.scale = scale
            return
        }
        return nil
    }

    public var cellPixelWidth: Int { Self.cellWidth * scale }
    public var cellPixelHeight: Int { Self.cellHeight * scale }

    public var supportsLookDirections: Bool { rows >= Self.v2Rows }

    public func frameRect(state: PetdexSpriteState, frameIndex: Int) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard state.row < rows else { return nil }
        let col = max(0, min(frameIndex, state.frameCount - 1))
        guard col < Self.columns else { return nil }
        return cellRect(row: state.row, column: col)
    }

    /// V2 rows 9–10: 16 clockwise look cells from up (`000°`).
    public func lookFrameRect(index: Int) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard supportsLookDirections,
              (0..<PetdexLookDirection.count).contains(index)
        else { return nil }
        return cellRect(
            row: PetdexLookDirection.atlasRow(for: index),
            column: PetdexLookDirection.atlasColumn(for: index)
        )
    }

    private func cellRect(row: Int, column: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        (
            x: column * cellPixelWidth,
            y: row * cellPixelHeight,
            w: cellPixelWidth,
            h: cellPixelHeight
        )
    }
}

/// One of the 16 V2 look cells. Clockwise from up, matching Codex / petx.
public struct PetdexLookDirection: Sendable, Equatable, Hashable {
    public static let count = 16
    public static let stepDegrees = 22.5

    /// `0...15`; `0` is up / 12 o'clock.
    public var index: Int

    public init?(index: Int) {
        guard (0..<Self.count).contains(index) else { return nil }
        self.index = index
    }

    public var degrees: Double { Double(index) * Self.stepDegrees }

    public static func atlasRow(for index: Int) -> Int { 9 + index / 8 }
    public static func atlasColumn(for index: Int) -> Int { index % 8 }

    /// Quantize clockwise degrees from up into a look cell.
    public static func resolve(degrees: Double) -> PetdexLookDirection? {
        guard degrees.isFinite else { return nil }
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        let index = Int((normalized / stepDegrees).rounded()) % count
        return PetdexLookDirection(index: index)
    }

    /// Screen-space vector: `+x` right, `+y` down (petx). Zero / deadzone → `nil`.
    public static func resolve(
        deltaX: Double,
        deltaYDown: Double,
        deadzone: Double = 0
    ) -> PetdexLookDirection? {
        guard deltaX.isFinite, deltaYDown.isFinite else { return nil }
        let magnitude = hypot(deltaX, deltaYDown)
        if magnitude == 0 || magnitude <= max(0, deadzone) { return nil }
        // petx: atan2(x, -y) with y-down → clockwise degrees from up.
        let degrees = atan2(deltaX, -deltaYDown) * 180 / .pi
        return resolve(degrees: degrees)
    }
}

/// Maps aibo agent activity onto a Petdex atlas row.
public enum PetdexSpriteStateMapper {
    public static func state(for activity: AiboActivityState) -> PetdexSpriteState {
        switch activity {
        case .idle:
            return .idle
        case .thinking, .registered, .responding:
            return .jumping
        case .usingTool(let name):
            return isReviewTool(name) ? .review : .running
        case .waiting:
            return .waiting
        case .failed:
            return .failed
        case .done, .interrupted:
            return .waving
        }
    }

    private static func isReviewTool(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "read"
            || lower == "grep"
            || lower == "glob"
            || lower.contains("read_file")
            || lower.contains("search")
    }
}
