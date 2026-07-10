import Foundation

public enum SessionState: String, Sendable {
    case working, waitingForInput, idle, ended, unknown
}

public struct ToolUse: Equatable, Sendable {
    public let name: String
    public let targetPath: String?
    public init(name: String, targetPath: String? = nil) {
        self.name = name; self.targetPath = targetPath
    }
}

public enum EventKind: Equatable, Sendable {
    case userMessage(String)
    case assistantMessage(text: String, toolUses: [ToolUse])
    case system(String)
    case meta
    case unknown
}

public struct SessionEvent: Equatable, Sendable {
    public let timestamp: Date
    public let kind: EventKind
    public init(timestamp: Date, kind: EventKind) {
        self.timestamp = timestamp; self.kind = kind
    }
}
