import Foundation

/// Locates session transcript files for all supported providers.
/// Strictly read-only. A missing provider directory means that provider
/// is absent — never an error.
public struct SessionDiscovery: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var claudeProjectsDir: URL { home.appendingPathComponent(".claude/projects") }
    var codexSessionsDir: URL { home.appendingPathComponent(".codex/sessions") }

    public func sessionFiles() -> [(provider: Provider, url: URL)] {
        var out: [(Provider, URL)] = []
        out += jsonlFiles(under: claudeProjectsDir).map { (.claudeCode, $0) }
        out += jsonlFiles(under: codexSessionsDir).map { (.codex, $0) }
        return out
    }

    public func parseAll(modifiedWithin: TimeInterval? = nil) -> [ParsedSession] {
        let cutoff = modifiedWithin.map { Date().addingTimeInterval(-$0) }
        return sessionFiles().compactMap { provider, url in
            if let cutoff,
               let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                   .contentModificationDate,
               mtime < cutoff { return nil }
            // Files whose modification date can't be read are deliberately included (fail-open).
            switch provider {
            case .claudeCode: return try? ClaudeCodeParser.parse(fileAt: url)
            case .codex: return try? CodexParser.parse(fileAt: url)
            }
        }
    }

    private func jsonlFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { ($0 as? URL) }
            .filter { $0.pathExtension == "jsonl" }
    }
}
