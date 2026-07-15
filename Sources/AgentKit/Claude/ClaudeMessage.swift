import Foundation

/// Permission posture handed to the `claude` CLI for a headless run. AgentBar
/// never bypasses silently — the mode is always explicit and surfaced in the UI
/// so the user knows exactly how much the agent is allowed to touch.
public enum ClaudePermissionMode: String, Sendable, CaseIterable, Identifiable {
    /// Ask-style default: tools needing approval are denied in headless mode,
    /// so the agent can read and answer but won't edit files or run commands.
    case `default`
    /// File edits are auto-approved; other permissioned tools still gated.
    case acceptEdits
    /// Plan only — the agent proposes but performs no side effects.
    case plan
    /// Everything is allowed with no prompts. Powerful and dangerous.
    case bypassPermissions

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default: return "Read-only (default)"
        case .acceptEdits: return "Accept edits"
        case .plan: return "Plan only"
        case .bypassPermissions: return "Bypass permissions"
        }
    }

    public var explanation: String {
        switch self {
        case .default:
            return "Agent can read and answer, but file edits and commands that need approval are declined."
        case .acceptEdits:
            return "File edits are applied automatically. Other permissioned tools are still gated."
        case .plan:
            return "Agent only proposes a plan — no files changed, no commands run."
        case .bypassPermissions:
            return "No prompts at all. The agent can edit files and run commands freely — use with care."
        }
    }
}

/// A single headless request to the `claude` CLI. The prompt is delivered over
/// stdin (not argv) so arbitrarily large / multiline text is safe.
public struct ClaudeRequest: Sendable {
    public var prompt: String
    /// Resume an existing conversation by its session id (`claude --resume`).
    public var resumeSessionID: String?
    /// Working directory the CLI runs in (the session's project dir for replies).
    public var cwd: URL?
    /// Model override, e.g. "claude-haiku-4-5-20251001". nil = CLI default.
    public var model: String?
    public var permissionMode: ClaudePermissionMode
    /// Extra guidance appended to the system prompt.
    public var appendSystemPrompt: String?
    /// Additional directories the agent may touch (`--add-dir`).
    public var addDirs: [String]

    public init(prompt: String,
                resumeSessionID: String? = nil,
                cwd: URL? = nil,
                model: String? = nil,
                permissionMode: ClaudePermissionMode = .default,
                appendSystemPrompt: String? = nil,
                addDirs: [String] = []) {
        self.prompt = prompt
        self.resumeSessionID = resumeSessionID
        self.cwd = cwd
        self.model = model
        self.permissionMode = permissionMode
        self.appendSystemPrompt = appendSystemPrompt
        self.addDirs = addDirs
    }

    /// Builds the argv (excluding the executable and the prompt itself, which is
    /// piped over stdin). Pure and deterministic so it can be unit-tested
    /// without ever launching a process.
    ///
    /// `stream-json` output in `--print` mode requires `--verbose`, so the
    /// streaming variant always adds it.
    public func arguments(streaming: Bool) -> [String] {
        var args = ["--print", "--output-format", streaming ? "stream-json" : "json"]
        if streaming { args.append("--verbose") }
        args += ["--permission-mode", permissionMode.rawValue]
        if let resumeSessionID, !resumeSessionID.isEmpty {
            args += ["--resume", resumeSessionID]
        }
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        if let appendSystemPrompt, !appendSystemPrompt.isEmpty {
            args += ["--append-system-prompt", appendSystemPrompt]
        }
        for dir in addDirs where !dir.isEmpty {
            args += ["--add-dir", dir]
        }
        return args
    }
}

/// The terminal `result` record of a `claude` run, whether from one-shot JSON
/// or the last line of a stream.
public struct ClaudeResult: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let sessionID: String?
    public let costUSD: Double?
    public let durationMS: Int?
    public let numTurns: Int?

    public init(text: String, isError: Bool, sessionID: String? = nil,
                costUSD: Double? = nil, durationMS: Int? = nil, numTurns: Int? = nil) {
        self.text = text; self.isError = isError; self.sessionID = sessionID
        self.costUSD = costUSD; self.durationMS = durationMS; self.numTurns = numTurns
    }

    /// Parses a `--output-format json` payload. Throws `ClaudeCLIError.decodeFailed`
    /// if the bytes aren't a recognizable result object.
    public static func parse(json data: Data) throws -> ClaudeResult {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = from(object: obj) else {
            throw ClaudeCLIError.decodeFailed(String(data: data, encoding: .utf8) ?? "<non-utf8>")
        }
        return result
    }

    /// Builds a result from an already-decoded JSON object (the `type:"result"`
    /// record). Returns nil if the object isn't a result record.
    public static func from(object obj: [String: Any]) -> ClaudeResult? {
        guard (obj["type"] as? String) == "result" || obj["result"] != nil else { return nil }
        let isError = (obj["is_error"] as? Bool) ?? false
        let text = (obj["result"] as? String)
            ?? (obj["error"] as? String)
            ?? errorText(subtype: obj["subtype"] as? String, isError: isError)
        return ClaudeResult(
            text: text,
            isError: isError,
            sessionID: obj["session_id"] as? String,
            costUSD: (obj["total_cost_usd"] as? NSNumber)?.doubleValue,
            durationMS: (obj["duration_ms"] as? NSNumber)?.intValue,
            numTurns: (obj["num_turns"] as? NSNumber)?.intValue)
    }

    private static func errorText(subtype: String?, isError: Bool) -> String {
        switch subtype {
        case "error_max_turns": return "Run hit the maximum number of turns."
        case "error_during_execution": return "The agent errored during execution."
        default: return isError ? "The run ended with an error." : ""
        }
    }
}

/// A parsed line of `--output-format stream-json`. One raw line can yield
/// several events (an assistant turn with text and two tool calls → three
/// events), so parsing returns an array.
public enum ClaudeStreamEvent: Sendable, Equatable {
    case systemInit(sessionID: String?, model: String?)
    case assistantText(String)
    case toolUse(name: String, target: String?)
    case result(ClaudeResult)

    /// Parses one newline-delimited JSON record. Unrecognized / non-JSON lines
    /// produce no events (they're plumbing). Pure — no process, no I/O.
    public static func parse(line: String) -> [ClaudeStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        switch obj["type"] as? String {
        case "system" where (obj["subtype"] as? String) == "init":
            return [.systemInit(sessionID: obj["session_id"] as? String,
                                model: obj["model"] as? String)]
        case "assistant":
            return assistantEvents(from: obj)
        case "result":
            return ClaudeResult.from(object: obj).map { [.result($0)] } ?? []
        default:
            return []
        }
    }

    private static func assistantEvents(from obj: [String: Any]) -> [ClaudeStreamEvent] {
        guard let message = obj["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]] else { return [] }
        var out: [ClaudeStreamEvent] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                let t = (block["text"] as? String) ?? ""
                if !t.isEmpty { out.append(.assistantText(t)) }
            case "tool_use":
                let input = block["input"] as? [String: Any]
                let target = (input?["file_path"] as? String)
                    ?? (input?["path"] as? String)
                    ?? (input?["command"] as? String)
                out.append(.toolUse(name: (block["name"] as? String) ?? "?", target: target))
            default:
                break
            }
        }
        return out
    }
}

/// Prompt builders shared by the app and the CLI so both phrase requests to
/// Claude Code identically.
public enum ClaudePrompts {
    /// A natural-language security review of the audited inventory. Kept factual
    /// and non-alarmist; the CLI reads the actual skill/MCP/hook text inline.
    public static func auditReview(items: [AuditItem]) -> String {
        var out = """
        You are reviewing a developer's installed Claude Code / Codex configuration \
        for security risk. Below are their skills, MCP server configs, and hook \
        settings. For each item that deserves attention, give: the item name, a \
        one-line risk, and why it matters. Be concrete and calm — cite the exact \
        snippet. End with a short overall verdict. If nothing stands out, say so \
        plainly; do not invent risk. Do not run any tools — analyze the text only.

        Items (\(items.count)):

        """
        for item in items {
            out += "\n----- \(item.kind.rawValue): \(item.name) (\(item.sourcePath)) -----\n"
            out += item.content.prefix(6000)
            out += "\n"
        }
        return out
    }
}
