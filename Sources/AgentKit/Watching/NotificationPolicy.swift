import Foundation

/// One notification per transition into waitingForInput per session,
/// with a per-session cooldown so rapid turn cycles don't spam.
public struct NotificationPolicy {
    public var cooldown: TimeInterval = 60
    private var lastState: [String: SessionState] = [:]
    private var lastNotified: [String: Date] = [:]

    public init() {}

    public mutating func shouldNotify(sessionID: String, newState: SessionState,
                                      now: Date) -> Bool {
        let old = lastState[sessionID]
        lastState[sessionID] = newState
        guard newState == .waitingForInput, old != .waitingForInput else { return false }
        if let last = lastNotified[sessionID], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastNotified[sessionID] = now
        return true
    }
}
