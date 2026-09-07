import Foundation

/// Codex `update_plan` checklist progress shown in the agent capsule (`current/total`).
///
/// `current` is the 1-based index of the active todo (the `in_progress` step, else the
/// first not-yet-completed step, else `total` when every step is `completed`).
/// The capsule ring fills by `completed / total` — the step you are on does not count
/// until it is `completed`.
public struct AgentPlanProgress: Equatable, Sendable {
    /// 1-based index of the todo currently in focus.
    public var current: Int
    public var total: Int
    /// How many steps are already `completed` (drives the ring).
    public var completed: Int

    public init(current: Int, total: Int, completed: Int) {
        self.total = max(0, total)
        if self.total == 0 {
            self.current = 0
            self.completed = 0
        } else {
            self.current = min(max(current, 1), self.total)
            self.completed = min(max(completed, 0), self.total)
        }
    }

    /// Filled fraction of the capsule ring (`completed / total`).
    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// Derives progress from Codex plan step statuses (`pending` / `in_progress` / `completed`).
    public static func fromPlanStatuses(_ statuses: [String]) -> AgentPlanProgress? {
        guard !statuses.isEmpty else { return nil }
        let normalized = statuses.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let completed = normalized.filter { $0 == "completed" }.count
        let current: Int
        if let index = normalized.firstIndex(of: "in_progress") {
            current = index + 1
        } else if completed == normalized.count {
            current = normalized.count
        } else if let index = normalized.firstIndex(where: { $0 != "completed" }) {
            current = index + 1
        } else {
            current = 1
        }
        return AgentPlanProgress(
            current: current,
            total: normalized.count,
            completed: completed
        )
    }
}
