import XCTest
@testable import AgentKit

final class TolerantJSONLTests: XCTestCase {
    func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testSkipsMalformedLinesAndCounts() throws {
        let url = try write("""
        {"type":"user","n":1}
        THIS IS NOT JSON
        {"type":"assistant","n":2}
        {"truncated":
        """)
        let (objects, skipped) = try TolerantJSONL.objects(at: url)
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(skipped, 2)
        XCTAssertEqual(objects[0]["type"] as? String, "user")
    }

    func testEmptyFile() throws {
        let url = try write("")
        let (objects, skipped) = try TolerantJSONL.objects(at: url)
        XCTAssertTrue(objects.isEmpty)
        XCTAssertEqual(skipped, 0)
    }

    func testTimestampBothPrecisions() {
        XCTAssertNotNil(Timestamps.parse("2026-07-10T14:02:33.434Z"))
        XCTAssertNotNil(Timestamps.parse("2026-07-10T14:02:33Z"))
        XCTAssertNil(Timestamps.parse("not a date"))
        XCTAssertNil(Timestamps.parse(nil))
    }

    func testLossyUTF8DecodingWithInvalidBytes() throws {
        let validLine = """
        {"type":"valid","n":1}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jsonl")

        // Build data with valid line, newline, then invalid UTF-8 bytes, then another newline
        var data = Data()
        data.append(validLine.data(using: .utf8)!)
        data.append("\n".data(using: .utf8)!)
        data.append(contentsOf: [0xFF, 0xFE])  // Invalid UTF-8 sequence
        data.append("\n".data(using: .utf8)!)

        try data.write(to: url)
        let (objects, skipped) = try TolerantJSONL.objects(at: url)

        XCTAssertEqual(objects.count, 1, "Should parse the valid JSON line")
        XCTAssertEqual(skipped, 1, "Should count the line with invalid UTF-8 as skipped")
        XCTAssertEqual(objects[0]["type"] as? String, "valid")
    }
}
