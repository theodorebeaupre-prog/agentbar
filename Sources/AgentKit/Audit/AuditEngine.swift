import Foundation

public enum AuditEngine {
    public static let disclaimer =
        "No flags does not mean guaranteed safe. Rules are heuristic."

    public static func scan(_ items: [AuditItem],
                            rules: [AuditRule] = builtinRules) -> [AuditFinding] {
        var out: [AuditFinding] = []
        for item in items {
            for rule in rules {
                if let scope = rule.appliesTo, !scope.contains(item.kind) { continue }
                for pattern in rule.patterns {
                    guard let re = try? NSRegularExpression(
                        pattern: pattern, options: [.caseInsensitive]) else { continue }
                    let range = NSRange(item.content.startIndex..., in: item.content)
                    if let m = re.firstMatch(in: item.content, range: range),
                       let r = Range(m.range, in: item.content) {
                        out.append(AuditFinding(
                            ruleID: rule.id, severity: rule.severity, title: rule.title,
                            itemName: item.name,
                            excerpt: excerpt(around: r, in: item.content),
                            explanation: rule.explanation))
                        break // one finding per rule per item
                    }
                }
            }
        }
        return out.sorted { $0.severity > $1.severity }
    }

    private static func excerpt(around r: Range<String.Index>, in s: String) -> String {
        let line = s.lineRange(for: r)
        return String(s[line]).trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            .description
    }
}
