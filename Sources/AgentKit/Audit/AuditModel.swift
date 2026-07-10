import Foundation

public enum AuditItemKind: String, Sendable { case skill, mcpServer, hook }

public struct AuditItem: Sendable {
    public let name: String
    public let kind: AuditItemKind
    public let sourcePath: String
    public let content: String
    public init(name: String, kind: AuditItemKind, sourcePath: String, content: String) {
        self.name = name; self.kind = kind; self.sourcePath = sourcePath; self.content = content
    }
}

public enum Severity: String, Comparable, Sendable {
    case yellow, red
    public static func < (a: Severity, b: Severity) -> Bool { a == .yellow && b == .red }
}

public struct AuditFinding: Equatable, Hashable, Sendable {
    public let ruleID: String
    public let severity: Severity
    public let title: String
    public let itemName: String
    public let excerpt: String
    public let explanation: String
}

public struct AuditRule: Sendable {
    public let id: String
    public let severity: Severity
    public let title: String
    public let explanation: String
    /// NSRegularExpression patterns, case-insensitive, matched per item content.
    public let patterns: [String]
    /// nil = applies to every item kind.
    public let appliesTo: Set<AuditItemKind>?
    public init(id: String, severity: Severity, title: String, explanation: String,
                patterns: [String], appliesTo: Set<AuditItemKind>?) {
        self.id = id; self.severity = severity; self.title = title
        self.explanation = explanation; self.patterns = patterns; self.appliesTo = appliesTo
    }
}
