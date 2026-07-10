public enum Provider: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
