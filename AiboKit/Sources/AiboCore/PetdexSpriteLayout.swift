import Foundation

/// Codex / Petdex atlas layout: 8 columns × 9 (v1) or 11 (v2) rows of 192×208 cells.
public enum PetdexSpriteState: String, Sendable, CaseIterable, Equatable {
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

    public func frameRect(state: PetdexSpriteState, frameIndex: Int) -> (x: Int, y: Int, w: Int, h: Int)? {
        guard state.row < rows else { return nil }
        let col = max(0, min(frameIndex, state.frameCount - 1))
        guard col < Self.columns else { return nil }
        return (
            x: col * cellPixelWidth,
            y: state.row * cellPixelHeight,
            w: cellPixelWidth,
            h: cellPixelHeight
        )
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
