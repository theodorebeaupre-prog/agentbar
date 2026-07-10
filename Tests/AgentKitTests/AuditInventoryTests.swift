import XCTest
@testable import AgentKit

final class AuditInventoryTests: XCTestCase {
    func makeFakeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("audithome-" + UUID().uuidString)
        let fm = FileManager.default
        let skill = home.appendingPathComponent(".claude/skills/my-skill")
        try fm.createDirectory(at: skill, withIntermediateDirectories: true)
        try "# My skill\nDo things.".write(
            to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"x":{"command":"npx","args":["-y","x@latest"]}}}"#.write(
            to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        return home
    }

    func testCollectsSkillsAndMcpConfigs() throws {
        let items = AuditInventory(home: try makeFakeHome()).collect()
        XCTAssertTrue(items.contains { $0.kind == .skill && $0.name == "my-skill" })
        XCTAssertTrue(items.contains { $0.kind == .mcpServer })
    }

    func testEmptyHomeYieldsNoItemsNoCrash() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bare-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        XCTAssertTrue(AuditInventory(home: home).collect().isEmpty)
    }

    func testEndToEndScanFindsUnpinnedMcp() throws {
        let items = AuditInventory(home: try makeFakeHome()).collect()
        let findings = AuditEngine.scan(items)
        XCTAssertTrue(findings.contains { $0.ruleID == "unpinned-source" })
    }
}
