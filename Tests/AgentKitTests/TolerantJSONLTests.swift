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
}
