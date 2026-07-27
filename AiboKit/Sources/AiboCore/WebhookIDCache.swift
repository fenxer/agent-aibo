import Foundation

/// Remembers recent webhook delivery IDs for idempotent handling.
public struct WebhookIDCache: Sendable {
    private var order: [String] = []
    private var seen: Set<String> = []
    private let capacity: Int

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    /// Returns `true` if this ID was already recorded.
    public mutating func containsOrInsert(_ id: String) -> Bool {
        if seen.contains(id) { return true }
        seen.insert(id)
        order.append(id)
        while order.count > capacity {
            let removed = order.removeFirst()
            seen.remove(removed)
        }
        return false
    }
}
