import XCTest
@testable import AgentKit

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(AgentKitInfo.version, "0.1.0")
    }
}
