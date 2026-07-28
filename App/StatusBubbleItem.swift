import Foundation

/// One status bubble in the stacked display.
struct StatusBubbleItem: Identifiable, Equatable, Sendable {
    var id: String
    /// Status / body text shown beside the agent capsule.
    var text: String
    var lastEventAt: Date
    /// When true, a click/tap clears the bubble (used for `.failed`).
    var isDismissible: Bool = false
    /// When true, status text cycles trailing `.` / `..` / `...`. Off for terminal states.
    var animatesEllipsis: Bool = true
    /// Label inside the agent capsule (e.g. "Cursor").
    var agentName: String = ""
    /// Template image asset name for the capsule icon, if any.
    var iconAssetName: String? = nil
    /// Last path component of the workspace / cwd, when known.
    var projectName: String? = nil
    /// Active model label, when known.
    var modelName: String? = nil
}
