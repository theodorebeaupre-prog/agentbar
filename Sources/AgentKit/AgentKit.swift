/// AgentKit — engine for discovering, parsing, watching, replaying, and
/// auditing local coding-agent data. Foundation-only.
///
/// Discovery, parsing, watching, replay, and audit are strictly read-only. The
/// one exception is the `Claude/` subsystem (`ClaudeCLI`), which drives the
/// user's *local* `claude` command in headless mode so AgentBar can also act —
/// reply to a session, ask a question, or run an AI-assisted audit. It shells
/// out to the already-installed, already-authenticated CLI: no API key, no
/// network code of our own.
public enum AgentKitInfo {
    public static let version = "0.2.0"
}
