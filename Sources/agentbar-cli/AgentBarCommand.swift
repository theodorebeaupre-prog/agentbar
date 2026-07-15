import ArgumentParser
import Foundation
import AgentKit

@main
struct AgentBar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentbar",
        abstract: "Mission control for your coding agents. Native, free, 100% local.",
        version: AgentKitInfo.version,
        subcommands: [Status.self, Watch.self, Replay.self, Audit.self, Ask.self, Reply.self],
        defaultSubcommand: Status.self)
}

func currentSnapshots() -> [SessionSnapshot] {
    let now = Date()
    return SessionDiscovery().parseAll(modifiedWithin: 48 * 3600)
        .map { SessionSnapshot(session: $0.session,
                               state: StateClassifier.classify(events: $0.events, now: now)) }
        .sorted { ($0.session.lastEventAt ?? .distantPast)
                > ($1.session.lastEventAt ?? .distantPast) }
}

/// All parsed sessions, most-recent first — the index space shared by `replay`
/// and `reply` so an index means the same session in both.
func recentSessions() -> [ParsedSession] {
    SessionDiscovery().parseAll(modifiedWithin: nil)
        .sorted { ($0.session.lastEventAt ?? .distantPast)
                > ($1.session.lastEventAt ?? .distantPast) }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the current state of all agent sessions.")
    func run() {
        print(TextRendering.statusTable(currentSnapshots()))
    }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Live-updating session status. Ctrl-C to exit.")
    func run() throws {
        while true {
            print("\u{1B}[2J\u{1B}[H", terminator: "") // clear + home
            print(TextRendering.statusTable(currentSnapshots()))
            print("\nRefreshing every 2s — Ctrl-C to exit.")
            Thread.sleep(forTimeInterval: 2)
        }
    }
}

struct Replay: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the timeline of a session (most recent by default).")
    @Argument(help: "Index into the recent-session list (0 = most recent).")
    var index: Int = 0
    @Flag(help: "Emit JSON.") var json = false

    func run() throws {
        let parsed = recentSessions()
        guard parsed.indices.contains(index) else {
            throw ValidationError("No session at index \(index). Found \(parsed.count).")
        }
        let entries = ReplayBuilder.timeline(from: parsed[index].events)
        if json {
            let objs: [[String: Any]] = entries.map { e in
                var o: [String: Any] = ["ts": ISO8601DateFormatter().string(from: e.timestamp)]
                if let el = e.elapsed { o["elapsed"] = el }
                switch e.kind {
                case .prompt(let t): o["kind"] = "prompt"; o["text"] = t
                case .response(let t): o["kind"] = "response"; o["text"] = t
                case .toolCall(let n, let target):
                    o["kind"] = "toolCall"; o["name"] = n
                    if let target { o["target"] = target }
                case .fileTouched(let p): o["kind"] = "fileTouched"; o["path"] = p
                }
                return o
            }
            let data = try JSONSerialization.data(withJSONObject: objs,
                                                  options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
        } else {
            let s = parsed[index].session
            print("Session: \(s.projectName) — \(s.title ?? "untitled") (\(s.provider.displayName))\n")
            print(TextRendering.timelineText(entries))
        }
    }
}

struct Audit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Heuristic security scan of installed skills, MCP configs, and hooks.")
    @Flag(help: "Emit JSON.") var json = false
    @Flag(help: "Also ask the local Claude Code CLI for a natural-language review.")
    var ai = false
    @Option(help: "Model for the AI review (default: CLI default).") var model: String?

    func run() async throws {
        let items = AuditInventory().collect()
        let findings = AuditEngine.scan(items)
        if json {
            let objs = findings.map { f -> [String: String] in
                ["rule": f.ruleID, "severity": f.severity.rawValue, "title": f.title,
                 "item": f.itemName, "excerpt": f.excerpt, "explanation": f.explanation]
            }
            let result: [String: Any] = [
                "disclaimer": AuditEngine.disclaimer,
                "findings": objs
            ]
            let data = try JSONSerialization.data(withJSONObject: result,
                                                  options: [.prettyPrinted])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("Scanned \(items.count) items.")
            print(TextRendering.auditReport(findings))
        }

        if ai {
            let cli = ClaudeCLI()
            guard cli.isAvailable else {
                FileHandle.standardError.write(Data("\n(AI review skipped: `claude` not found.)\n".utf8))
                if findings.contains(where: { $0.severity == .red }) { throw ExitCode(1) }
                return
            }
            FileHandle.standardError.write(Data("\nAsking Claude Code for a review…\n".utf8))
            let req = ClaudeRequest(prompt: ClaudePrompts.auditReview(items: items),
                                    model: model, permissionMode: .plan)
            let result = try await runStreaming(cli, req)
            printFooter(result)
        }

        if findings.contains(where: { $0.severity == .red }) {
            throw ExitCode(1)
        }
    }
}

struct Ask: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ask the local Claude Code CLI a one-off question (no API key).")
    @Argument(help: "Your prompt. Quote it if it contains spaces.") var prompt: String
    @Option(help: "Model to use (default: CLI default).") var model: String?
    @Flag(help: "Emit the raw JSON result.") var json = false

    func run() async throws {
        let cli = try requireCLI()
        let req = ClaudeRequest(prompt: prompt, model: model, permissionMode: .default)
        if json {
            let r = try await cli.run(req)
            printJSON(r)
        } else {
            let r = try await runStreaming(cli, req)
            printFooter(r)
        }
    }
}

struct Reply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a text reply into an existing Claude Code session (resumes it).")
    @Argument(help: "Index into the recent-session list (0 = most recent).") var index: Int
    @Argument(help: "Your reply. Quote it if it contains spaces.") var prompt: String
    @Option(help: "Model to use (default: CLI default).") var model: String?
    @Option(help: "Permission mode: default | acceptEdits | plan | bypassPermissions.")
    var permissionMode: ClaudePermissionMode = .acceptEdits
    @Flag(help: "Emit the raw JSON result.") var json = false

    func run() async throws {
        let cli = try requireCLI()
        let sessions = recentSessions()
        guard sessions.indices.contains(index) else {
            throw ValidationError("No session at index \(index). Found \(sessions.count).")
        }
        let session = sessions[index].session
        guard session.provider == .claudeCode else {
            throw ValidationError("Session \(index) is a \(session.provider.displayName) session; only Claude Code sessions can be resumed.")
        }
        guard let resumeID = session.resumeID else {
            throw ValidationError("Couldn't determine a resume id for session \(index).")
        }
        let cwd = session.cwd.map { URL(fileURLWithPath: $0) }
        FileHandle.standardError.write(Data(
            "Resuming \(session.projectName) — \(session.title ?? "untitled") [\(permissionMode.displayName)]\n".utf8))
        let req = ClaudeRequest(prompt: prompt, resumeSessionID: resumeID, cwd: cwd,
                                model: model, permissionMode: permissionMode)
        if json {
            printJSON(try await cli.run(req))
        } else {
            printFooter(try await runStreaming(cli, req))
        }
    }
}

// MARK: - Shared CLI helpers

extension ClaudePermissionMode: ExpressibleByArgument {
    public init?(argument: String) { self.init(rawValue: argument) }
}

func requireCLI() throws -> ClaudeCLI {
    let cli = ClaudeCLI()
    guard cli.isAvailable else {
        throw ValidationError("The `claude` command isn't installed or isn't on PATH. Install Claude Code and try again.")
    }
    return cli
}

/// Streams a run to the terminal: assistant text to stdout as it arrives, tool
/// calls dimmed to stderr. Returns the final result record.
@discardableResult
func runStreaming(_ cli: ClaudeCLI, _ req: ClaudeRequest) async throws -> ClaudeResult? {
    var final: ClaudeResult?
    for try await ev in cli.stream(req) {
        switch ev {
        case .systemInit:
            break
        case .assistantText(let t):
            FileHandle.standardOutput.write(Data(t.utf8))
        case .toolUse(let name, let target):
            let line = "\n\u{1B}[2m→ \(name)\(target.map { " · \($0)" } ?? "")\u{1B}[0m\n"
            FileHandle.standardError.write(Data(line.utf8))
        case .result(let r):
            final = r
        }
    }
    print("")
    return final
}

func printFooter(_ result: ClaudeResult?) {
    guard let result else { return }
    var bits: [String] = []
    if let c = result.costUSD { bits.append(String(format: "$%.4f", c)) }
    if let d = result.durationMS { bits.append(String(format: "%.1fs", Double(d) / 1000)) }
    if let n = result.numTurns { bits.append("\(n) turn\(n == 1 ? "" : "s")") }
    if result.isError { bits.append("error") }
    guard !bits.isEmpty else { return }
    FileHandle.standardError.write(Data("\u{1B}[2m[\(bits.joined(separator: " · "))]\u{1B}[0m\n".utf8))
}

func printJSON(_ result: ClaudeResult) {
    var o: [String: Any] = ["text": result.text, "is_error": result.isError]
    if let s = result.sessionID { o["session_id"] = s }
    if let c = result.costUSD { o["total_cost_usd"] = c }
    if let d = result.durationMS { o["duration_ms"] = d }
    if let n = result.numTurns { o["num_turns"] = n }
    if let data = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted]) {
        print(String(data: data, encoding: .utf8)!)
    }
}
