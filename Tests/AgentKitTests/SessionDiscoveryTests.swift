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
}
