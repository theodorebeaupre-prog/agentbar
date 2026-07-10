import Foundation

public struct Session: Identifiable, Equatable, Sendable {
    public let provider: Provider
    public let fileURL: URL
    public var title: String?
    public var cwd: String?
    public var gitBranch: String?
    public var startedAt: Date?
    public var lastEventAt: Date?

    public var id: String { provider.rawValue + ":" + fileURL.path }
    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public init(provider: Provider, fileURL: URL, title: String?, cwd: String?,
                gitBranch: String?, startedAt: Date?, lastEventAt: Date?) {
        self.provider = provider; self.fileURL = fileURL; self.title = title
        self.cwd = cwd; self.gitBranch = gitBranch
        self.startedAt = startedAt; self.lastEventAt = lastEventAt
    }
}
