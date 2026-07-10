import Foundation

/// Caches parsed sessions keyed by file path, invalidated by (mtime, size).
///
/// Why mtime+size: a transcript file is only ever appended to by its owning
/// CLI, so a change in either its modification time or its byte size is a
/// necessary condition for its parsed contents to have changed. Checking both
/// (rather than mtime alone) guards against the coarse mtime resolution some
/// filesystems expose, where two distinct writes within the same tick would
/// otherwise be indistinguishable.
///
/// Why a class with a lock rather than a value type: `SessionDiscovery` is a
/// struct that call sites are free to copy, but the cache must be shared
/// across those copies to be useful — a `let` reference-type property
/// survives struct copies while still being mutated in place. The lock makes
/// the cache safe to share across the watcher's background queue and any
/// other caller without requiring `SessionDiscovery` itself to become an
/// actor (AgentKit stays Foundation-only, no Swift Concurrency actors here).
///
/// Why instance-scoped rather than a static/shared singleton: a CLI one-shot
/// constructs a fresh `SessionDiscovery` per invocation and parses every file
/// exactly once regardless, so it gets no benefit either way — but a shared
/// process-wide cache would leak entries across unrelated `SessionDiscovery`
/// instances (e.g. ones pointed at a different `home` in tests) and never
/// bound its size. An instance cache scopes the benefit to exactly the
/// long-lived callers that repeatedly re-parse the same directory tree
/// (`SessionWatcher`, the app), which is the only place steady-state CPU
/// mattered.
final class ParseCache: @unchecked Sendable {
    private struct Entry {
        let mtime: Date
        let size: Int
        let parsed: ParsedSession
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// Returns the cached parse for `path` if present and its mtime/size
    /// still match, else nil.
    func lookup(path: String, mtime: Date, size: Int) -> ParsedSession? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[path], e.mtime == mtime, e.size == size else { return nil }
        return e.parsed
    }

    func store(path: String, mtime: Date, size: Int, parsed: ParsedSession) {
        lock.lock(); defer { lock.unlock() }
        entries[path] = Entry(mtime: mtime, size: size, parsed: parsed)
    }
}

/// Locates session transcript files for all supported providers.
/// Strictly read-only. A missing provider directory means that provider
/// is absent — never an error.
public struct SessionDiscovery: Sendable {
    public let home: URL
    private let cache = ParseCache()

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
            let resourceValues = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = resourceValues?.contentModificationDate
            let size = resourceValues?.fileSize

            if let cutoff, let mtime, mtime < cutoff { return nil }
            // Files whose modification date can't be read are deliberately included (fail-open).

            // Only files with a readable mtime AND size participate in the
            // cache — without a size, a growing file (append) could reuse a
            // stale parse if the mtime happened to collide with a resolution
            // boundary. Missing resourceValues is rare (fail-open above) and
            // simply forgoes caching for that one file, at worst re-parsing it.
            if let mtime, let size,
               let cached = cache.lookup(path: url.path, mtime: mtime, size: size) {
                return cached
            }

            let parsed: ParsedSession?
            switch provider {
            case .claudeCode: parsed = try? ClaudeCodeParser.parse(fileAt: url)
            case .codex: parsed = try? CodexParser.parse(fileAt: url)
            }
            if let parsed, let mtime, let size {
                cache.store(path: url.path, mtime: mtime, size: size, parsed: parsed)
            }
            return parsed
        }
    }

    /// Passes an explicit errorHandler that skips unreadable entries and keeps
    /// walking, rather than letting the default (nil) behavior silently abort
    /// the remaining traversal: one unreadable subtree must not make every
    /// session under sibling directories vanish (mirrors AuditInventory's
    /// skillItems(under:namePrefix:)).
    private func jsonlFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }) else { return [] }
        return e.compactMap { ($0 as? URL) }
            .filter { $0.pathExtension == "jsonl" }
    }
}
