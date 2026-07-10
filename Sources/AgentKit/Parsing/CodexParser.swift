import Foundation

/// Parses `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
/// session_meta payload carries cwd/session_id; response_item payloads carry
/// messages and function calls. Pinned by Fixtures/codex-basic.jsonl.
public enum CodexParser {
    public static func parse(fileAt url: URL) throws -> ParsedSession {
        let (objects, skipped) = try TolerantJSONL.objects(at: url)
        var events: [SessionEvent] = []
        var cwd: String?
        var firstTS: Date?, lastTS: Date?

        for obj in objects {
            guard let ts = Timestamps.parse(obj["timestamp"] as? String) else { continue }
            if firstTS == nil { firstTS = ts }
            lastTS = ts
            let payload = obj["payload"] as? [String: Any]
            if (obj["type"] as? String) == "session_meta" {
                cwd = payload?["cwd"] as? String
                events.append(SessionEvent(timestamp: ts, kind: .meta))
                continue
            }
            events.append(SessionEvent(timestamp: ts, kind: kind(of: payload)))
        }

        let session = Session(provider: .codex, fileURL: url, title: nil,
                              cwd: cwd, gitBranch: nil,
                              startedAt: firstTS, lastEventAt: lastTS)
        return ParsedSession(session: session, events: events, skippedLines: skipped)
    }

    private static func kind(of payload: [String: Any]?) -> EventKind {
        guard let payload else { return .unknown }
        switch payload["type"] as? String {
        case "message":
            let blocks = (payload["content"] as? [[String: Any]]) ?? []
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            switch payload["role"] as? String {
            case "user": return .userMessage(text)
            case "assistant": return .assistantMessage(text: text, toolUses: [])
            default:
                // e.g. role "developer": injected sandbox/permissions instructions
                // re-sent each turn, not a real user prompt or assistant reply.
                return .meta
            }
        case "function_call", "custom_tool_call":
            let name = (payload["name"] as? String) ?? "?"
            return .assistantMessage(text: "", toolUses: [ToolUse(name: name)])
        case "user_message":
            // event_msg-level echo of the user's turn (flat "message" field,
            // distinct from the response_item "message" block shape above).
            return .userMessage((payload["message"] as? String) ?? "")
        case "agent_message":
            // event_msg-level echo of the assistant's turn commentary.
            return .assistantMessage(text: (payload["message"] as? String) ?? "", toolUses: [])
        default:
            // Includes reasoning, function_call_output, custom_tool_call_output,
            // token_count, task_started/task_complete, patch_apply_end, and any
            // other payload shape we haven't special-cased — all plumbing/meta.
            return .meta
        }
    }
}
