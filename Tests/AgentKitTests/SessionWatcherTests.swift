import XCTest
@testable import AgentKit

final class SessionWatcherTests: XCTestCase {
    func testEmitsInitialSnapshotAndReactsToAppend() async throws {
        // fake home with one Claude session
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchhome-" + UUID().uuidString)
        let dir = home.appendingPathComponent(".claude/projects/-p")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s1.jsonl")
        let now = ISO8601DateFormatter().string(from: .now)
        try #"{"type":"user","timestamp":"\#(now)","message":{"role":"user","content":"go"},"cwd":"/p"}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let watcher = SessionWatcher(discovery: SessionDiscovery(home: home),
                                     pollInterval: 0.2)
        var iterator = watcher.snapshots().makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first?.count, 1)
        XCTAssertEqual(first?.first?.state, .working) // fresh user message

        // append a finished assistant turn stamped 10s in the past (> settle 5s)
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        let line = "\n" + #"{"type":"assistant","timestamp":"\#(past)","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"cwd":"/p"}"#
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: line.data(using: .utf8)!)
        try handle.close()

        // drain until the state flips (bounded by test timeout)
        var state = first?.first?.state
        for _ in 0..<20 where state != .waitingForInput {
            state = (await iterator.next())?.first?.state
        }
        XCTAssertEqual(state, .waitingForInput)
        watcher.stop()
    }

    func testLateSubscriberDoesNotSwallowTransitionForExistingSubscriber() async throws {
        // fake home with one Claude session
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchhome-" + UUID().uuidString)
        let dir = home.appendingPathComponent(".claude/projects/-p")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s1.jsonl")
        let now = ISO8601DateFormatter().string(from: .now)
        try #"{"type":"user","timestamp":"\#(now)","message":{"role":"user","content":"go"},"cwd":"/p"}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let watcher = SessionWatcher(discovery: SessionDiscovery(home: home),
                                     pollInterval: 0.2)

        // Subscriber A subscribes first and gets its initial value.
        var iteratorA = watcher.snapshots().makeAsyncIterator()
        let firstA = await iteratorA.next()
        XCTAssertEqual(firstA?.first?.state, .working)

        // Subscriber B subscribes after A, before the fs change lands.
        var iteratorB = watcher.snapshots().makeAsyncIterator()
        let firstB = await iteratorB.next()
        XCTAssertEqual(firstB?.first?.state, .working)

        // append a finished assistant turn stamped 10s in the past (> settle 5s)
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        let line = "\n" + #"{"type":"assistant","timestamp":"\#(past)","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"cwd":"/p"}"#
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: line.data(using: .utf8)!)
        try handle.close()

        // drain both iterators until the state flips (bounded by test timeout)
        var stateA = firstA?.first?.state
        for _ in 0..<20 where stateA != .waitingForInput {
            stateA = (await iteratorA.next())?.first?.state
        }
        XCTAssertEqual(stateA, .waitingForInput)

        var stateB = firstB?.first?.state
        for _ in 0..<20 where stateB != .waitingForInput {
            stateB = (await iteratorB.next())?.first?.state
        }
        XCTAssertEqual(stateB, .waitingForInput)

        watcher.stop()
    }
}
