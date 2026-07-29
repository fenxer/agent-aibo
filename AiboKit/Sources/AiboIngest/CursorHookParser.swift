import AiboCore
import Foundation

public struct ParsedHookLine: Sendable, Equatable {
    public var session: SessionKey
    public var transition: StateTransition
    public var eventName: String
    /// Last path component of workspace root / cwd when present in the payload.
    public var projectName: String? = nil
    /// Model id / label when the hook payload includes one.
    public var modelName: String? = nil
    /// True for Cursor Task/subagent sessions (dashed “Subagent” capsule).
    public var isSubagent: Bool = false
}

public enum CursorHookParser {
    public static func parse(jsonLine: String) throws -> ParsedHookLine? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return nil }

        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["hookEventName"] as? String)
        guard let eventName, !eventName.isEmpty else { return nil }

        if eventName == "subagentStart" {
            return parseSubagentStart(payload: payload, eventName: eventName)
        }
        if eventName == "subagentStop" {
            return parseSubagentStop(payload: payload, eventName: eventName)
        }

        guard let conversationID = payload["conversation_id"] as? String,
              !conversationID.isEmpty
        else {
            return nil
        }

        let toolName = payload["tool_name"] as? String
        let stopStatus = payload["status"] as? String
        guard let transition = CursorEventMapper.transition(
            eventName: eventName,
            toolName: toolName,
            stopStatus: stopStatus
        ) else {
            return nil
        }

        return ParsedHookLine(
            session: SessionKey(agent: .cursor, conversationID: conversationID),
            transition: transition,
            eventName: eventName,
            projectName: HookPayloadFields.projectName(from: payload),
            modelName: HookPayloadFields.modelName(from: payload),
            isSubagent: HookPayloadFields.isSubagentTranscript(payload["transcript_path"] as? String)
        )
    }

    /// `subagentStart` keys the new session by `subagent_id` (not the parent conversation).
    private static func parseSubagentStart(
        payload: [String: Any],
        eventName: String
    ) -> ParsedHookLine? {
        guard let subagentID = payload["subagent_id"] as? String,
              !subagentID.isEmpty
        else {
            return nil
        }
        guard let transition = CursorEventMapper.transition(eventName: eventName) else {
            return nil
        }
        let model = (payload["subagent_model"] as? String)
            .flatMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            ?? HookPayloadFields.modelName(from: payload)
        return ParsedHookLine(
            session: SessionKey(agent: .cursor, conversationID: subagentID),
            transition: transition,
            eventName: eventName,
            projectName: HookPayloadFields.projectName(from: payload),
            modelName: model,
            isSubagent: true
        )
    }

    private static func parseSubagentStop(
        payload: [String: Any],
        eventName: String
    ) -> ParsedHookLine? {
        guard let subagentID = Self.subagentSessionID(from: payload) else { return nil }
        let stopStatus = payload["status"] as? String
        guard let transition = CursorEventMapper.transition(
            eventName: eventName,
            stopStatus: stopStatus
        ) else {
            return nil
        }
        return ParsedHookLine(
            session: SessionKey(agent: .cursor, conversationID: subagentID),
            transition: transition,
            eventName: eventName,
            projectName: HookPayloadFields.projectName(from: payload),
            modelName: HookPayloadFields.modelName(from: payload),
            isSubagent: true
        )
    }

    /// Prefer `…/subagents/<id>.jsonl`, then common-schema `conversation_id`.
    private static func subagentSessionID(from payload: [String: Any]) -> String? {
        if let path = payload["agent_transcript_path"] as? String,
           let id = HookPayloadFields.subagentID(fromTranscriptPath: path)
        {
            return id
        }
        if let path = payload["transcript_path"] as? String,
           let id = HookPayloadFields.subagentID(fromTranscriptPath: path)
        {
            return id
        }
        if let conversationID = payload["conversation_id"] as? String,
           !conversationID.isEmpty
        {
            return conversationID
        }
        return nil
    }
}
