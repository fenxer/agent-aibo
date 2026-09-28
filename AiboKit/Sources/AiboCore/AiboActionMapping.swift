import Foundation

/// Desktop aibo behaviors that are not driven by agent hooks.
public enum AiboUserAction: String, Sendable, CaseIterable, Equatable, Hashable, Identifiable {
    case dragLeft = "drag-left"
    case dragRight = "drag-right"

    public var id: String { rawValue }
}

public enum AiboDisplayPresentation: Equatable, Sendable {
    case sprite(PetdexSpriteState, activity: AiboActivityState)
    case look(PetdexLookDirection)
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

    /// Outcome hooks (done / failed / interrupted) first, then the newest
    /// non-idle hook. Same timestamp: either session is acceptable.
    public static func preferredSession(
        sessions: [SessionKey: SessionSnapshot]
    ) -> (key: SessionKey, snapshot: SessionSnapshot)? {
        if let outcome = newestSession(in: sessions, matching: \.isOutcome) {
            return outcome
        }
        if let hook = newestSession(in: sessions, matching: { $0 != .idle }) {
            return hook
        }
        return newestSession(in: sessions, matching: { _ in true })
    }

    /// Overlay (onboarding, etc.) > outcome hooks > latest hook > drag > follow-mouse > idle.
    public static func presentation(
        sessions: [SessionKey: SessionSnapshot],
        spriteFor: (SessionKey, SessionSnapshot) -> PetdexSpriteState,
        dragSprite: PetdexSpriteState?,
        lookDirection: PetdexLookDirection?,
        overlaySprite: PetdexSpriteState? = nil
    ) -> AiboDisplayPresentation {
        if let overlaySprite {
            return .sprite(overlaySprite, activity: .idle)
        }
        if let hook = hookDrivenPresentation(sessions: sessions, spriteFor: spriteFor) {
            return hook
        }
        if let dragSprite {
            return .sprite(dragSprite, activity: .idle)
        }
        if let lookDirection {
            return .look(lookDirection)
        }
        return .sprite(.idle, activity: .idle)
    }

    /// Hook-driven sprite only. `nil` when every session is idle, so drag and
    /// follow-mouse stay outside this value and the desktop view can cache it.
    public static func hookDrivenPresentation(
        sessions: [SessionKey: SessionSnapshot],
        spriteFor: (SessionKey, SessionSnapshot) -> PetdexSpriteState
    ) -> AiboDisplayPresentation? {
        guard let pair = preferredHookSession(in: sessions) else { return nil }
        return .sprite(spriteFor(pair.key, pair.snapshot), activity: pair.snapshot.activity)
    }

    private static func preferredHookSession(
        in sessions: [SessionKey: SessionSnapshot]
    ) -> (key: SessionKey, snapshot: SessionSnapshot)? {
        if let outcome = newestSession(in: sessions, matching: \.isOutcome) {
            return outcome
        }
        return newestSession(in: sessions, matching: { $0 != .idle })
    }

    private static func newestSession(
        in sessions: [SessionKey: SessionSnapshot],
        matching: (AiboActivityState) -> Bool
    ) -> (key: SessionKey, snapshot: SessionSnapshot)? {
        sessions
            .filter { matching($0.value.activity) }
            .max { $0.value.lastEventAt < $1.value.lastEventAt }
            .map { ($0.key, $0.value) }
    }
}
