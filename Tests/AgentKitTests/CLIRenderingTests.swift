import XCTest
@testable import AgentKit

final class CLIRenderingTests: XCTestCase {
    func testStatusTableShowsWaitingMarker() {
        let s = Session(provider: .claudeCode, fileURL: URL(fileURLWithPath: "/t/a.jsonl"),
                        title: "Fix bug", cwd: "/Users/dev/Proj", gitBranch: "main",
                        startedAt: nil, lastEventAt: Date(timeIntervalSince1970: 1_800_000_000))
        let table = TextRendering.statusTable(
            [SessionSnapshot(session: s, state: .waitingForInput)],
            now: Date(timeIntervalSince1970: 1_800_000_060))
        XCTAssertTrue(table.contains("WAITING"))
        XCTAssertTrue(table.contains("Proj"))
        XCTAssertTrue(table.contains("1m ago"))
    }

    func testRelativeFormatting() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(TextRendering.relative(now.addingTimeInterval(-30), now: now), "30s ago")
        XCTAssertEqual(TextRendering.relative(now.addingTimeInterval(-90), now: now), "1m ago")
        XCTAssertEqual(TextRendering.relative(now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(TextRendering.relative(nil, now: now), "—")
    }

    func testAuditReportContainsDisclaimerAndExcerpt() {
        let f = AuditFinding(ruleID: "shell-danger", severity: .red,
                             title: "Dangerous shell command", itemName: "bad-skill",
                             excerpt: "rm -rf ~/Library", explanation: "Destructive.")
        let report = TextRendering.auditReport([f])
        XCTAssertTrue(report.contains("bad-skill"))
        XCTAssertTrue(report.contains("rm -rf ~/Library"))
        XCTAssertTrue(report.contains(AuditEngine.disclaimer))
    }

    func testAuditReportEmptyStillHasDisclaimer() {
        XCTAssertTrue(TextRendering.auditReport([]).contains(AuditEngine.disclaimer))
    }
}
