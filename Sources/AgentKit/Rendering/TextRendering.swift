import Foundation

public enum TextRendering {
    public static func relative(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "—" }
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }

    static func stateLabel(_ state: SessionState) -> String {
        switch state {
        case .working: return "● WORKING"
        case .waitingForInput: return "◉ WAITING"
        case .idle: return "○ idle"
        case .ended: return "  ended"
        case .unknown: return "? unknown"
        }
    }

    public static func statusTable(_ snaps: [SessionSnapshot], now: Date = .now) -> String {
        guard !snaps.isEmpty else { return "No agent sessions found." }
        var rows: [[String]] = [["STATE", "PROJECT", "PROVIDER", "TITLE", "LAST ACTIVITY"]]
        for s in snaps {
            rows.append([stateLabel(s.state), s.session.projectName,
                         s.session.provider.displayName,
                         s.session.title ?? "—",
                         relative(s.session.lastEventAt, now: now)])
        }
        let widths = (0..<rows[0].count).map { c in
            rows.map { $0[c].count }.max()! }
        return rows.map { row in
            zip(row, widths).map { $0.padding(toLength: $1 + 2, withPad: " ",
                                              startingAt: 0) }.joined()
        }.joined(separator: "\n")
    }

    public static func timelineText(_ entries: [TimelineEntry]) -> String {
        guard !entries.isEmpty else { return "Empty session." }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm:ss"
        return entries.map { e in
            let gap = e.elapsed.map { $0 >= 1 ? String(format: " (+%.0fs)", $0) : "" } ?? ""
            let body: String
            switch e.kind {
            case .prompt(let t): body = "🧑 " + t.prefix(120)
            case .response(let t): body = "🤖 " + t.prefix(120)
            case .toolCall(let n, let target): body = "🔧 \(n)" + (target.map { " → \($0)" } ?? "")
            case .fileTouched(let p): body = "✏️  \(p)"
            }
            return "\(df.string(from: e.timestamp))\(gap)  \(body)"
        }.joined(separator: "\n")
    }

    public static func auditReport(_ findings: [AuditFinding]) -> String {
        var out = ""
        if findings.isEmpty {
            out += "No findings.\n"
        } else {
            let byItem = Dictionary(grouping: findings, by: \.itemName)
            for (item, fs) in byItem.sorted(by: { $0.key < $1.key }) {
                out += "\n\(item)\n"
                for f in fs.sorted(by: { $0.severity > $1.severity }) {
                    let flag = f.severity == .red ? "🔴" : "🟡"
                    out += "  \(flag) [\(f.ruleID)] \(f.title)\n"
                    out += "     ⤷ \(f.excerpt)\n"
                    out += "     \(f.explanation)\n"
                }
            }
        }
        out += "\n⚠️  \(AuditEngine.disclaimer)\n"
        return out
    }
}
