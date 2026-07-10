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
}
