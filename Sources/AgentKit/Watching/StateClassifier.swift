import Foundation

/// Pure heuristic state machine. Age gates first (ended > idle), then the
/// last *meaningful* event decides. Meta/system noise is skipped so a stray
/// attachment can't mask a "waiting for input" turn.
public enum StateClassifier {
    public static func classify(events: [SessionEvent], now: Date,
                                thresholds: StateThresholds = .init()) -> SessionState {
        guard let last = events.last else { return .unknown }
        let age = now.timeIntervalSince(last.timestamp)
        if age >= thresholds.ended { return .ended }
        if age >= thresholds.idle { return .idle }

        guard let meaningful = events.reversed().first(where: {
            switch $0.kind { case .meta, .system: return false; default: return true }
        }) else { return .unknown }

        switch meaningful.kind {
        case .assistantMessage(_, let toolUses):
            if toolUses.contains(where: { $0.name == "AskUserQuestion" }) {
                return .waitingForInput
            }
            if toolUses.isEmpty {
                // Turn looks finished; give the file a moment to settle.
                // Measure settle delay from the meaningful event, not trailing noise.
                let settleAge = now.timeIntervalSince(meaningful.timestamp)
                return settleAge >= thresholds.settle ? .waitingForInput : .working
            }
            return .working
        case .userMessage:
            return .working
        case .unknown:
            return .unknown
        case .meta, .system:
            return .unknown // unreachable: filtered above
        }
    }
}
