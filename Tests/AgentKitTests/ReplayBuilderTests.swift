import XCTest
@testable import AgentKit

final class ReplayBuilderTests: XCTestCase {
    func testTimelineFromMixedEvents() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            SessionEvent(timestamp: t0, kind: .userMessage("Fix the bug")),
            SessionEvent(timestamp: t0.addingTimeInterval(5), kind: .meta),
            SessionEvent(timestamp: t0.addingTimeInterval(10), kind: .assistantMessage(
                text: "On it.",
                toolUses: [ToolUse(name: "Edit", targetPath: "/p/src/a.ts"),
                           ToolUse(name: "Bash")])),
            SessionEvent(timestamp: t0.addingTimeInterval(20), kind: .assistantMessage(
                text: "Done.", toolUses: [])),
        ]
        let tl = ReplayBuilder.timeline(from: events)
        XCTAssertEqual(tl.map(\.kind), [
            .prompt("Fix the bug"),
            .response("On it."),
            .fileTouched(path: "/p/src/a.ts"),   // Edit is a write tool
            .toolCall(name: "Bash", target: nil),
            .response("Done."),
        ])
        XCTAssertNil(tl[0].elapsed)
        XCTAssertEqual(tl[1].elapsed, 10) // meta skipped, elapsed spans real entries
    }

    func testEmptyAssistantTextProducesNoResponseEntry() {
        let e = [SessionEvent(timestamp: .now, kind: .assistantMessage(
            text: "", toolUses: [ToolUse(name: "Read")]))]
        XCTAssertEqual(ReplayBuilder.timeline(from: e).map(\.kind),
                       [.toolCall(name: "Read", target: nil)])
    }
}
