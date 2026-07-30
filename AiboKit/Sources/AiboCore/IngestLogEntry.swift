import Foundation

/// One local-agent hook ingest record (DEBUG diagnostics).
public struct IngestLogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// When aibo processed the line (drain uses "now", not the original hook time).
    public var at: Date
    /// `drain` summary, or `event` for a single hook line.
    public var kind: String
    /// `queue` or `socket` for events; nil for drain summaries.
    public var source: String?
    /// Parsed from queue filename when `source == queue`.
    public var queuedAt: Date?
    public var eventName: String?
    public var agent: String?
    public var conversationID: String?
    public var projectName: String?
    public var modelName: String?
    public var isSubagent: Bool?
    /// e.g. `thinking`, `usingTool:Shell`, `removeSession`.
    public var activity: String?
    /// `applied` / `ignored` / `malformed` / `summary`.
    public var outcome: String
    public var detail: String?
    /// Non-idle session count after applying this event (events only).
    public var activeSessionCount: Int?

    public init(
        id: String = UUID().uuidString,
        at: Date = Date(),
        kind: String,
        source: String? = nil,
        queuedAt: Date? = nil,
        eventName: String? = nil,
        agent: String? = nil,
        conversationID: String? = nil,
        projectName: String? = nil,
        modelName: String? = nil,
        isSubagent: Bool? = nil,
        activity: String? = nil,
        outcome: String,
        detail: String? = nil,
        activeSessionCount: Int? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.source = source
        self.queuedAt = queuedAt
        self.eventName = eventName
        self.agent = agent
        self.conversationID = conversationID
        self.projectName = projectName
        self.modelName = modelName
        self.isSubagent = isSubagent
        self.activity = activity
        self.outcome = outcome
        self.detail = detail
        self.activeSessionCount = activeSessionCount
    }
}
