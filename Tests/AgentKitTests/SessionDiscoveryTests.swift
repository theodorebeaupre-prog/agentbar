import XCTest
@testable import AgentKit

final class SessionDiscoveryTests: XCTestCase {
    /// Builds a fake HOME with both providers' layouts.
    func makeFakeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("fakehome-" + UUID().uuidString)
        let claude = home.appendingPathComponent(".claude/projects/-Users-dev-CoolProj")
        let codex = home.appendingPathComponent(".codex/sessions/2026/07/10")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureURL("claude-basic.jsonl"),
            to: claude.appendingPathComponent("aaaa-1111.jsonl"))
        try FileManager.default.copyItem(at: fixtureURL("codex-basic.jsonl"),
            to: codex.appendingPathComponent("rollout-2026-07-10T14-00-00-cx1.jsonl"))
        return home
    }

    func testDiscoversBothProviders() throws {
        let d = SessionDiscovery(home: try makeFakeHome())
        let files = d.sessionFiles()
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(files.map(\.provider)), [.claudeCode, .codex])
    }

    func testMissingProviderDirIsSilentlyAbsent() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let d = SessionDiscovery(home: home)
        XCTAssertTrue(d.sessionFiles().isEmpty)
    }

    func testParseAllReturnsParsedSessions() throws {
        let d = SessionDiscovery(home: try makeFakeHome())
        let all = d.parseAll(modifiedWithin: nil)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.session.lastEventAt != nil })
    }

    func testParseAllModifiedWithinCutoffExcludesOldFiles() throws {
        let home = try makeFakeHome()
        // Find all session files.
        let sessionFiles = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: [.isRegularFileKey]
        )?.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  let isRegular = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegular else { return nil }
            return url
        }.sorted { $0.path < $1.path } ?? []

        guard sessionFiles.count >= 2 else {
            XCTFail("Expected at least 2 .jsonl files in fake home")
            return
        }

        // Backdate one file to 2 hours in the past.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -7200)],
            ofItemAtPath: sessionFiles[0].path
        )

        // Pin the other file to now.
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: sessionFiles[1].path
        )

        let d = SessionDiscovery(home: home)

        // With a 1-hour (3600 second) cutoff, the 2-hour-old file should be excluded.
        let withinOneHour = d.parseAll(modifiedWithin: 3600)
        XCTAssertEqual(withinOneHour.count, 1, "Should exclude files modified more than 1 hour ago")

        // With no cutoff, both files should be included.
        let withoutCutoff = d.parseAll(modifiedWithin: nil)
        XCTAssertEqual(withoutCutoff.count, 2, "Should include all files when no cutoff is specified")
    }

    /// Sanity check for the mtime+size-keyed parse cache added to SessionDiscovery:
    /// calling parseAll() twice on an unchanged tree through the *same* instance
    /// (so the cache is actually shared) must yield identical results.
    func testParseAllTwiceYieldsSameResults() throws {
        let d = SessionDiscovery(home: try makeFakeHome())
        let first = d.parseAll(modifiedWithin: nil)
        let second = d.parseAll(modifiedWithin: nil)
        XCTAssertEqual(first.count, second.count)
        let firstIDs = Set(first.map(\.session.id))
        let secondIDs = Set(second.map(\.session.id))
        XCTAssertEqual(firstIDs, secondIDs)
        for p in first {
            let match = second.first { $0.session.id == p.session.id }
            XCTAssertEqual(match?.events.count, p.events.count)
        }
    }

    /// Behavioral test for cache invalidation: appending a line to one file
    /// (with its mtime bumped forward, since some filesystems have coarse
    /// mtime resolution and a same-tick append could otherwise collide with a
    /// mtime-only cache key) must cause that file's re-parse to reflect the
    /// new event, while the untouched sibling file keeps parsing correctly
    /// from the still-valid cache entry.
    func testCacheInvalidatesOnAppendButNotUntouchedFile() throws {
        let home = try makeFakeHome()
        let d = SessionDiscovery(home: home)

        let claudeFile = home.appendingPathComponent(
            ".claude/projects/-Users-dev-CoolProj/aaaa-1111.jsonl")
        let codexFile = home.appendingPathComponent(
            ".codex/sessions/2026/07/10/rollout-2026-07-10T14-00-00-cx1.jsonl")

        // The enumerator resolves symlinks (e.g. /var -> /private/var on
        // macOS) while our constructed URLs don't, so compare by filename
        // suffix rather than URL/path equality — both fixture filenames are
        // unique within this fake home.
        func isClaudeFile(_ p: ParsedSession) -> Bool {
            p.session.fileURL.path.hasSuffix(claudeFile.lastPathComponent)
        }
        func isCodexFile(_ p: ParsedSession) -> Bool {
            p.session.fileURL.path.hasSuffix(codexFile.lastPathComponent)
        }

        let before = d.parseAll(modifiedWithin: nil)
        let claudeBefore = before.first(where: isClaudeFile)
        let codexBefore = before.first(where: isCodexFile)
        XCTAssertNotNil(claudeBefore)
        XCTAssertNotNil(codexBefore)

        // Append a new, later-timestamped user message to the Claude file only.
        let extraLine = #"{"type":"user","timestamp":"2026-07-10T15:00:00.000Z","sessionId":"fx-1","cwd":"/Users/dev/CoolProj","message":{"role":"user","content":"One more thing"}}"#
        let handle = try FileHandle(forWritingTo: claudeFile)
        handle.seekToEndOfFile()
        handle.write(("\n" + extraLine + "\n").data(using: .utf8)!)
        try handle.close()

        // Bump mtime forward explicitly so the cache key is guaranteed to change
        // even on filesystems with coarse mtime resolution.
        let existingMtime = try claudeFile.resourceValues(
            forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()
        try FileManager.default.setAttributes(
            [.modificationDate: existingMtime.addingTimeInterval(5)],
            ofItemAtPath: claudeFile.path)

        let after = d.parseAll(modifiedWithin: nil)
        let claudeAfter = after.first(where: isClaudeFile)
        let codexAfter = after.first(where: isCodexFile)

        XCTAssertNotNil(claudeAfter)
        XCTAssertGreaterThan(claudeAfter!.events.count, claudeBefore!.events.count,
            "Appended file must be re-parsed, not served from the stale cache entry")

        XCTAssertNotNil(codexAfter)
        XCTAssertEqual(codexAfter!.events.count, codexBefore!.events.count,
            "Untouched file must still parse correctly (and can be served from cache)")
    }
}
