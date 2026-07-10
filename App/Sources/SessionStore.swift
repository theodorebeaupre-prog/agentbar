import SwiftUI
import AgentKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var snapshots: [SessionSnapshot] = []
    var waitingCount: Int { snapshots.filter { $0.state == .waitingForInput }.count }

    private let watcher = SessionWatcher(discovery: SessionDiscovery())
    private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            guard let stream = self?.watcher.snapshots() else { return }
            for await snaps in stream {
                self?.snapshots = snaps
            }
        }
    }

    deinit { watcher.stop() }
}
