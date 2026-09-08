import Foundation

/// First-launch tour gate. Updates and later launches must not replay it.
public enum OnboardingGate: Sendable {
    /// - Parameter storedCompleted: `nil` when the flag has never been written.
    /// - Parameter hasExistingInstallEvidence: library, saved position, or other
    ///   leftovers from a previous version — those users skip the tour.
    public static func shouldPresentOnLaunch(
        storedCompleted: Bool?,
        hasExistingInstallEvidence: Bool
    ) -> Bool {
        if let storedCompleted {
            return !storedCompleted
        }
        return !hasExistingInstallEvidence
    }
}
