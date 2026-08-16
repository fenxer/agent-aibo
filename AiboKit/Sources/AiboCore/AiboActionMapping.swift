import Foundation

/// Desktop aibo behaviors that are not driven by agent hooks.
public enum AiboUserAction: String, Sendable, CaseIterable, Equatable, Hashable, Identifiable {
    case dragLeft = "drag-left"
    case dragRight = "drag-right"

    public var id: String { rawValue }
}

public enum AiboActionMapping {
    public static func defaultSprite(for action: AiboUserAction) -> PetdexSpriteState {
        switch action {
        case .dragLeft: .runningLeft
        case .dragRight: .runningRight
        }
    }

    public static func resolve(
        _ action: AiboUserAction,
        overrides: [String: String]
    ) -> PetdexSpriteState {
        if let raw = overrides[action.rawValue],
           let sprite = PetdexSpriteState(rawValue: raw)
        {
            return sprite
        }
        return defaultSprite(for: action)
    }

    /// Drag / pointer-look occupy the idle slot. Hook-driven sprites always win.
    public static func overlay(
        hookSprite: PetdexSpriteState,
        userActionSprite: PetdexSpriteState?
    ) -> PetdexSpriteState {
        guard hookSprite == .idle, let userActionSprite else { return hookSprite }
        return userActionSprite
    }
}
