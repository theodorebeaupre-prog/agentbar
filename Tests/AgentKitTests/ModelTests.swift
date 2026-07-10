import XCTest
@testable import AgentKit

final class ModelTests: XCTestCase {
    func testSessionIdentityAndProjectName() {
        let s = Session(
            provider: .claudeCode,
            fileURL: URL(fileURLWithPath: "/tmp/x.jsonl"),
            title: nil, cwd: "/Users/dev/CoolProj",
            gitBranch: "main", startedAt: nil, lastEventAt: nil
        )
        XCTAssertEqual(s.id, "claude-code:/tmp/x.jsonl")
        XCTAssertEqual(s.projectName, "CoolProj")
    }

    func testProjectNameFallback() {
        let s = Session(provider: .codex, fileURL: URL(fileURLWithPath: "/tmp/y.jsonl"),
                        title: nil, cwd: nil, gitBranch: nil, startedAt: nil, lastEventAt: nil)
        XCTAssertEqual(s.projectName, "?")
    }

    func testDefaultThresholds() {
        let t = StateThresholds()
        XCTAssertEqual(t.active, 30); XCTAssertEqual(t.settle, 5)
        XCTAssertEqual(t.idle, 1800); XCTAssertEqual(t.ended, 86400)
    }
}
