import XCTest
@testable import AgentKit

final class NotificationPolicyTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testNotifiesOnTransitionIntoWaiting() {
        var p = NotificationPolicy()
        XCTAssertFalse(p.shouldNotify(sessionID: "s", newState: .working, now: t0))
        XCTAssertTrue(p.shouldNotify(sessionID: "s", newState: .waitingForInput,
                                     now: t0.addingTimeInterval(1)))
    }
    func testNoRepeatWhileStillWaiting() {
        var p = NotificationPolicy()
        _ = p.shouldNotify(sessionID: "s", newState: .waitingForInput, now: t0)
        XCTAssertFalse(p.shouldNotify(sessionID: "s", newState: .waitingForInput,
                                      now: t0.addingTimeInterval(10)))
    }
    func testCooldownSuppressesRapidReTransition() {
        var p = NotificationPolicy()
        _ = p.shouldNotify(sessionID: "s", newState: .waitingForInput, now: t0)
        _ = p.shouldNotify(sessionID: "s", newState: .working, now: t0.addingTimeInterval(5))
        XCTAssertFalse(p.shouldNotify(sessionID: "s", newState: .waitingForInput,
                                      now: t0.addingTimeInterval(30))) // < 60s cooldown
        _ = p.shouldNotify(sessionID: "s", newState: .working, now: t0.addingTimeInterval(61))
        XCTAssertTrue(p.shouldNotify(sessionID: "s", newState: .waitingForInput,
                                     now: t0.addingTimeInterval(90)))
    }
    func testSessionsAreIndependent() {
        var p = NotificationPolicy()
        _ = p.shouldNotify(sessionID: "a", newState: .waitingForInput, now: t0)
        XCTAssertTrue(p.shouldNotify(sessionID: "b", newState: .waitingForInput,
                                     now: t0.addingTimeInterval(1)))
    }
}
