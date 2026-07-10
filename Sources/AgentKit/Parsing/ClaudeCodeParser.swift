import Foundation

/// Parses `~/.claude/projects/<escaped-cwd>/<uuid>.jsonl` transcripts.
/// Field mapping pinned by Fixtures/claude-basic.jsonl (format is undocumented
/// and may drift; unknown shapes degrade to .meta/.unknown, never crash).
public enum ClaudeCodeParser {
    public static func parse(fileAt url: URL) throws -> ParsedSession {
        let (objects, skipped) = try TolerantJSONL.objects(at: url)
        var events: [SessionEvent] = []
        var title: String?, cwd: String?, branch: String?
        var firstTS: Date?, lastTS: Date?

        for obj in objects {
            if cwd == nil { cwd = obj["cwd"] as? String }
            if branch == nil { branch = obj["gitBranch"] as? String }
            if let t = obj["customTitle"] as? String { title = t }

            let ts = Timestamps.parse(obj["timestamp"] as? String)
            if let ts {
                if firstTS == nil { firstTS = ts }
                lastTS = ts
            }
            guard let ts else {
                // untimestamped records (custom-title, last-prompt…) are metadata
                continue
            }
            events.append(SessionEvent(timestamp: ts, kind: kind(of: obj)))
        }

        let session = Session(provider: .claudeCode, fileURL: url, title: title,
                              cwd: cwd, gitBranch: branch,
                              startedAt: firstTS, lastEventAt: lastTS)
        return ParsedSession(session: session, events: events, skippedLines: skipped)
    }

    private static func kind(of obj: [String: Any]) -> EventKind {
        switch obj["type"] as? String {
        case "user":
            guard let message = obj["message"] as? [String: Any] else { return .unknown }
            if let text = message["content"] as? String {
                return .userMessage(text)
            }
            if let blocks = message["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { b -> String? in
                    (b["type"] as? String) == "text" ? b["text"] as? String : nil
                }
                // tool_result-only "user" records are plumbing, not prompts
                return texts.isEmpty ? .meta : .userMessage(texts.joined(separator: "\n"))
            }
            return .unknown
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { return .unknown }
            var text = "", toolUses: [ToolUse] = []
            for b in blocks {
                switch b["type"] as? String {
                case "text":
                    text += (b["text"] as? String) ?? ""
                case "tool_use":
                    let input = b["input"] as? [String: Any]
                    toolUses.append(ToolUse(
                        name: (b["name"] as? String) ?? "?",
                        targetPath: input?["file_path"] as? String))
                default: break
                }
            }
            return .assistantMessage(text: text, toolUses: toolUses)
        case "system":
            return .system((obj["content"] as? String) ?? "")
        case "attachment", "queue-operation", "last-prompt", "custom-title":
            return .meta
        default:
            return .unknown
        }
    }
}
