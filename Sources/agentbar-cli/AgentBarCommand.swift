import ArgumentParser
import Foundation
import AgentKit

@main
struct AgentBar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentbar",
        abstract: "Mission control for your coding agents. Native, free, 100% local.",
        version: AgentKitInfo.version,
        subcommands: [Status.self, Watch.self, Replay.self, Audit.self],
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
        let parsed = SessionDiscovery().parseAll(modifiedWithin: nil)
            .sorted { ($0.session.lastEventAt ?? .distantPast)
                    > ($1.session.lastEventAt ?? .distantPast) }
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

struct Audit: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Heuristic security scan of installed skills, MCP configs, and hooks.")
    @Flag(help: "Emit JSON.") var json = false

    func run() throws {
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
        if findings.contains(where: { $0.severity == .red }) {
            throw ExitCode(1)
        }
    }
}
