import Foundation

public struct Session: Identifiable, Equatable, Sendable {
    public let provider: Provider
    public let fileURL: URL
    public var title: String?
    public var cwd: String?
    public var gitBranch: String?
    public var startedAt: Date?
    public var lastEventAt: Date?
    /// The CLI's own session identifier, when the transcript records one.
    /// For Claude Code it is the `sessionId` field (equivalently the file's
    /// UUID stem); for Codex it is `session_meta.payload.session_id`. Needed to
    /// resume a conversation via `claude --resume <id>`.
    public var sessionID: String?

    public var id: String { provider.rawValue + ":" + fileURL.path }
    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// The identifier to hand to `claude --resume`. Falls back to the file's
    /// UUID stem when the transcript itself carried no `sessionId` (older
    /// Claude Code transcripts), since the filename *is* the session UUID.
    public var resumeID: String? {
        if let sessionID, !sessionID.isEmpty { return sessionID }
        guard provider == .claudeCode else { return nil }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
    }

    public init(provider: Provider, fileURL: URL, title: String?, cwd: String?,
                gitBranch: String?, startedAt: Date?, lastEventAt: Date?,
                sessionID: String? = nil) {
        self.provider = provider; self.fileURL = fileURL; self.title = title
        self.cwd = cwd; self.gitBranch = gitBranch
        self.startedAt = startedAt; self.lastEventAt = lastEventAt
        self.sessionID = sessionID
    }
}
