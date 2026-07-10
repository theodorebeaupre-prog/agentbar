import Foundation

public struct ParsedSession {
    public let session: Session
    public let events: [SessionEvent]
    public let skippedLines: Int
    public init(session: Session, events: [SessionEvent], skippedLines: Int) {
        self.session = session; self.events = events; self.skippedLines = skippedLines
    }
}
