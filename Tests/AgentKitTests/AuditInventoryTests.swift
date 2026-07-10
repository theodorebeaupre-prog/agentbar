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

    /// A second fixture builder covering the collection behaviors not touched
    /// by `makeFakeHome()`: two same-named plugin skills from different
    /// plugins, a Codex MCP config, and Claude hook settings.
    func makeFullFakeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("audithome-full-" + UUID().uuidString)
        let fm = FileManager.default

        let toolkitSkill = home.appendingPathComponent(
            ".claude/plugins/cache/marketplace/toolkit/1.0.0/skills/review")
        try fm.createDirectory(at: toolkitSkill, withIntermediateDirectories: true)
        try "# Review\nToolkit's review skill.".write(
            to: toolkitSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let otherSkill = home.appendingPathComponent(
            ".claude/plugins/cache/marketplace/other/2.0.0/skills/review")
        try fm.createDirectory(at: otherSkill, withIntermediateDirectories: true)
        try "# Review\nOther's review skill.".write(
            to: otherSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let codexDir = home.appendingPathComponent(".codex")
        try fm.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try "[mcp_servers.x]\ncommand = \"npx\"\n".write(
            to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let claudeDir = home.appendingPathComponent(".claude")
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try #"{"hooks":{"PreToolUse":[]}}"#.write(
            to: claudeDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        return home
    }

    func testPluginSkillsAreQualifiedByPluginAndDistinct() throws {
        let items = AuditInventory(home: try makeFullFakeHome()).collect()
        let toolkitReview = items.first { $0.name == "plugin:toolkit/review" }
        let otherReview = items.first { $0.name == "plugin:other/review" }

        XCTAssertNotNil(toolkitReview)
        XCTAssertNotNil(otherReview)
        XCTAssertEqual(toolkitReview?.kind, .skill)
        XCTAssertEqual(otherReview?.kind, .skill)
        XCTAssertNotEqual(toolkitReview?.sourcePath, otherReview?.sourcePath)
    }

    func testCodexConfigCollectedAsMcpServer() throws {
        let items = AuditInventory(home: try makeFullFakeHome()).collect()
        XCTAssertTrue(items.contains {
            $0.kind == .mcpServer && $0.name == ".codex/config.toml"
        })
    }

    func testClaudeSettingsCollectedAsHook() throws {
        let items = AuditInventory(home: try makeFullFakeHome()).collect()
        XCTAssertTrue(items.contains {
            $0.kind == .hook && $0.name == ".claude/settings.json"
        })
    }

    func testClaudeSettingsLocalCollectedAsHook() throws {
        let home = try makeFullFakeHome()
        let claudeDir = home.appendingPathComponent(".claude")
        try #"{"hooks":{"PostToolUse":[]}}"#.write(
            to: claudeDir.appendingPathComponent("settings.local.json"),
            atomically: true, encoding: .utf8)

        let items = AuditInventory(home: home).collect()
        XCTAssertTrue(items.contains {
            $0.kind == .hook && $0.name == ".claude/settings.local.json"
        })
    }
}
