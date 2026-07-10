import XCTest
@testable import AgentKit

final class StateClassifierTests: XCTestCase {
    let t = StateThresholds() // active 30, settle 5, idle 1800, ended 86400
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func event(_ kind: EventKind, ageSeconds: TimeInterval) -> SessionEvent {
        SessionEvent(timestamp: now.addingTimeInterval(-ageSeconds), kind: kind)
    }
    func classify(_ events: [SessionEvent]) -> SessionState {
        StateClassifier.classify(events: events, now: now, thresholds: t)
    }

    func testNoEventsIsUnknown() {
        XCTAssertEqual(classify([]), .unknown)
    }
    func testVeryOldIsEnded() {
        XCTAssertEqual(classify([event(.assistantMessage(text: "done", toolUses: []),
                                       ageSeconds: 90_000)]), .ended)
    }
    func testStaleIsIdle() {
        XCTAssertEqual(classify([event(.assistantMessage(text: "done", toolUses: []),
                                       ageSeconds: 2_000)]), .idle)
    }
    func testAskUserQuestionIsImmediatelyWaiting() {
        XCTAssertEqual(classify([event(.assistantMessage(text: "",
            toolUses: [ToolUse(name: "AskUserQuestion")]), ageSeconds: 1)]),
            .waitingForInput)
    }
    func testFinishedAssistantMessageAfterSettleIsWaiting() {
        XCTAssertEqual(classify([event(.assistantMessage(text: "done", toolUses: []),
                                       ageSeconds: 10)]), .waitingForInput)
    }
    func testFinishedAssistantMessageWithinSettleIsWorking() {
        XCTAssertEqual(classify([event(.assistantMessage(text: "done", toolUses: []),
                                       ageSeconds: 2)]), .working)
    }
    func testAssistantWithToolUseIsWorking() {
        XCTAssertEqual(classify([event(.assistantMessage(text: "",
            toolUses: [ToolUse(name: "Bash")]), ageSeconds: 10)]), .working)
    }
    func testUserMessageLastIsWorking() {
        XCTAssertEqual(classify([event(.userMessage("go"), ageSeconds: 10)]), .working)
    }
    func testMetaLastFallsThroughToPreviousMeaningfulEvent() {
        // attachment noise after a finished assistant turn must not mask "waiting"
        XCTAssertEqual(classify([
            event(.assistantMessage(text: "done", toolUses: []), ageSeconds: 20),
            event(.meta, ageSeconds: 18),
        ]), .waitingForInput)
    }
    func testFreshMetaNoiseDoesNotResetSettleClock() {
        // Regression: trailing meta noise must not mask settled state.
        // Assistant finished 100s ago, meta arrived 2s ago → settle clock measures
        // the assistant message (100s), not the noise (2s).
        XCTAssertEqual(classify([
            event(.assistantMessage(text: "done", toolUses: []), ageSeconds: 100),
            event(.meta, ageSeconds: 2),
        ]), .waitingForInput)
    }
    func testUnknownKindIsUnknown() {
        XCTAssertEqual(classify([event(.unknown, ageSeconds: 10)]), .unknown)
    }
}
