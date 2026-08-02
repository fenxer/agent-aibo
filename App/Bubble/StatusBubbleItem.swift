import AiboCore
import Foundation

/// One status bubble in the stacked display.
struct StatusBubbleItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Local agent hooks: project/model header + agent capsule + status phrase.
        case agent
        /// Remote webhook: source + relative time header + status capsule + summary.
        case webhook
        /// Local health alert (e.g. tunnel down): fixed Warning header + red icon capsule.
        case warning
    }

    var id: String
    /// Body text beside the capsule (agent status phrase, or webhook summary).
    var text: String
    var lastEventAt: Date
    var kind: Kind = .agent
    /// When true, a click/tap clears the bubble (used for `.failed`).
    var isDismissible: Bool = false
    /// When true, status text cycles trailing `.` / `..` / `...`. Off for terminal states.
    var animatesEllipsis: Bool = true
    /// Local agent `.waiting` (approval), or Cursor `.usingTool` stall hint: CTA row with trailing arrow.
    var isAwaitingApproval: Bool = false
    /// Agent capsule label, or webhook `source` in the header.
    var agentName: String = ""
    /// Template image asset name for the agent capsule icon, if any.
    var iconAssetName: String? = nil
    /// Last path component of the workspace / cwd, when known (agent only).
    var projectName: String? = nil
    /// Active model label, when known (agent only).
    var modelName: String? = nil
    /// Webhook `status` shown in the capsule.
    var statusLabel: String? = nil
    /// Cursor Task/subagent: outline dashed capsule labeled “Subagent”.
    var isSubagent: Bool = false
    /// Local hook agent; used to activate the source app on tap. Nil for webhook/debug.
    var agent: AgentKind? = nil
}
