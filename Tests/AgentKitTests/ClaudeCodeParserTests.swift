import XCTest
@testable import AgentKit

final class ClaudeCodeParserTests: XCTestCase {
    func testParsesBasicSession() throws {
        let parsed = try ClaudeCodeParser.parse(fileAt: fixtureURL("claude-basic.jsonl"))
        XCTAssertEqual(parsed.session.provider, .claudeCode)
        XCTAssertEqual(parsed.session.title, "Login bug fix")
        XCTAssertEqual(parsed.session.cwd, "/Users/dev/CoolProj")
        XCTAssertEqual(parsed.session.gitBranch, "main")
        XCTAssertEqual(parsed.session.sessionID, "fx-1")
        XCTAssertEqual(parsed.session.resumeID, "fx-1")
        XCTAssertEqual(parsed.skippedLines, 0)

        // 5 timestamped events: user, attachment(meta), assistant, user(tool_result→meta),
        // assistant. custom-title has no timestamp, so it's metadata only.
        XCTAssertEqual(parsed.events.count, 5)
        XCTAssertEqual(parsed.events[0].kind, .userMessage("Fix the login bug"))
        XCTAssertEqual(parsed.events[1].kind, .meta)
        XCTAssertEqual(parsed.events[2].kind, .assistantMessage(
            text: "Looking at it.",
            toolUses: [ToolUse(name: "Edit", targetPath: "/Users/dev/CoolProj/src/login.ts")]))
        XCTAssertEqual(parsed.events[3].kind, .meta) // tool_result is plumbing, not a prompt
        XCTAssertEqual(parsed.events[4].kind, .assistantMessage(
            text: "Fixed. The null check was missing.", toolUses: []))

        XCTAssertEqual(parsed.session.startedAt,
                       Timestamps.parse("2026-07-10T14:00:00.000Z"))
        XCTAssertEqual(parsed.session.lastEventAt,
                       Timestamps.parse("2026-07-10T14:00:12.000Z"))
    }

    func testMalformedLinesAreSkippedNotFatal() throws {
        let parsed = try ClaudeCodeParser.parse(fileAt: fixtureURL("claude-malformed.jsonl"))
        XCTAssertEqual(parsed.skippedLines, 2)
        XCTAssertEqual(parsed.events.count, 2)
    }
}
