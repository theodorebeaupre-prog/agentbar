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

    /// Records a session's state without ever notifying. Callers use this to
    /// establish a baseline for sessions observed for the first time (e.g. the
    /// app's first snapshot batch at launch) — without it, every session that
    /// happens to already be `waitingForInput` at that moment would look like
    /// a fresh `nil → waitingForInput` transition and fire a notification, even
    /// though nothing actually just happened. After seeding, a genuine later
    /// transition (e.g. working → waitingForInput) still notifies normally.
    public mutating func seed(sessionID: String, state: SessionState) {
        lastState[sessionID] = state
    }
}
