import Foundation

public enum TimelineEntryKind: Equatable, Sendable {
    case prompt(String)
    case response(String)
    case toolCall(name: String, target: String?)
    case fileTouched(path: String)
}

public struct TimelineEntry: Equatable, Sendable {
    public let timestamp: Date
    public let elapsed: TimeInterval?
    public let kind: TimelineEntryKind
}

public enum ReplayBuilder {
    static let writeTools: Set<String> = ["Edit", "Write", "NotebookEdit"]

    public static func timeline(from events: [SessionEvent]) -> [TimelineEntry] {
        var out: [TimelineEntry] = []
        var previous: Date?
        func push(_ ts: Date, _ kind: TimelineEntryKind) {
            out.append(TimelineEntry(timestamp: ts,
                                     elapsed: previous.map { ts.timeIntervalSince($0) },
                                     kind: kind))
            previous = ts
        }
        for e in events {
            switch e.kind {
            case .userMessage(let text) where !text.isEmpty:
                push(e.timestamp, .prompt(text))
            case .assistantMessage(let text, let toolUses):
                if !text.isEmpty { push(e.timestamp, .response(text)) }
                for tu in toolUses {
                    if writeTools.contains(tu.name), let path = tu.targetPath {
                        push(e.timestamp, .fileTouched(path: path))
                    } else {
                        push(e.timestamp, .toolCall(name: tu.name, target: tu.targetPath))
                    }
                }
            default:
                continue
            }
        }
        return out
    }
}
