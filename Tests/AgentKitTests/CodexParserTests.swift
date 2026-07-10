import XCTest
@testable import AgentKit

final class CodexParserTests: XCTestCase {
    func testParsesBasicSession() throws {
        let parsed = try CodexParser.parse(fileAt: fixtureURL("codex-basic.jsonl"))
        XCTAssertEqual(parsed.session.provider, .codex)
        XCTAssertEqual(parsed.session.cwd, "/Users/dev/CoolProj")
        XCTAssertEqual(parsed.events.count, 10)
        XCTAssertEqual(parsed.events[0].kind, .meta) // session_meta
        XCTAssertEqual(parsed.events[1].kind, .userMessage("Fix the login bug"))
        XCTAssertEqual(parsed.events[2].kind,
                       .assistantMessage(text: "", toolUses: [ToolUse(name: "shell")]))
        XCTAssertEqual(parsed.events[3].kind,
                       .assistantMessage(text: "Done.", toolUses: []))

        // Types found in a real ~/.codex/sessions rollout (2026-07-10) not
        // present in the original fixture; anonymized samples added below.
        // event_msg user_message/agent_message are echoes of turns already
        // carried by response_item/message (the canonical channel), so they map
        // to .meta — otherwise replay would show every prompt/response twice.
        XCTAssertEqual(parsed.events[4].kind, .meta) // event_msg/user_message
        XCTAssertEqual(parsed.events[5].kind, .meta) // event_msg/agent_message
        XCTAssertEqual(parsed.events[6].kind,
                       .assistantMessage(text: "",
                                          toolUses: [ToolUse(name: "apply_patch")])) // custom_tool_call
        XCTAssertEqual(parsed.events[7].kind, .meta) // response_item/reasoning -> meta
        XCTAssertEqual(parsed.events[8].kind, .meta) // response_item/function_call_output -> meta
        XCTAssertEqual(parsed.events[9].kind, .meta) // message role "developer" -> meta, not assistant
    }
}
