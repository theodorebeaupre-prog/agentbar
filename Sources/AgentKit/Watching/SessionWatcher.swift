import Foundation

/// Watches provider session directories and emits state snapshots.
/// Strategy: directory-level DispatchSource where possible, plus a poll
/// timer as the universal fallback (covers appends, new files, and the
/// settle/idle timeouts which need re-evaluation without any fs event).
public final class SessionWatcher: @unchecked Sendable {
    private let discovery: SessionDiscovery
    private let thresholds: StateThresholds
    private let pollInterval: TimeInterval
    private let watchWindow: TimeInterval
    private let queue = DispatchQueue(label: "agentbar.watcher")
    private var timer: DispatchSourceTimer?
    private var dirSources: [DispatchSourceFileSystemObject] = []
    private var continuations: [UUID: AsyncStream<[SessionSnapshot]>.Continuation] = [:]
    private var lastEmitted: [SessionSnapshot]?

    public init(discovery: SessionDiscovery,
                thresholds: StateThresholds = .init(),
                pollInterval: TimeInterval = 15,
                watchWindow: TimeInterval = 48 * 3600) {
        self.discovery = discovery
        self.thresholds = thresholds
        self.pollInterval = pollInterval
        self.watchWindow = watchWindow
    }

    public func snapshots() -> AsyncStream<[SessionSnapshot]> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async {
                self.continuations[id] = continuation
                self.startIfNeeded()
                continuation.yield(self.computeSnapshots()) // immediate first value
            }
            continuation.onTermination = { [weak self] _ in
                self?.queue.async { self?.continuations[id] = nil }
            }
        }
    }

    public func stop() {
        queue.async {
            self.timer?.cancel(); self.timer = nil
            self.dirSources.forEach { $0.cancel() }; self.dirSources = []
            self.continuations.values.forEach { $0.finish() }
            self.continuations = [:]
        }
    }

    // MARK: - queue-confined

    private func startIfNeeded() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollInterval,
                   repeating: pollInterval, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.refresh() }
        t.resume()
        timer = t
        watchDirectory(discovery.claudeProjectsDir)
        watchDirectory(discovery.codexSessionsDir)
    }

    private func watchDirectory(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return } // provider absent: poll timer still covers it
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleDebouncedRefresh() }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSources.append(src)
    }

    private var debouncePending = false
    private func scheduleDebouncedRefresh() {
        guard !debouncePending else { return }
        debouncePending = true
        queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
            self.debouncePending = false
            self.refresh()
        }
    }

    private func refresh() {
        let snaps = computeSnapshots()
        guard snaps != lastEmitted else { return }
        lastEmitted = snaps
        continuations.values.forEach { $0.yield(snaps) }
    }

    private func computeSnapshots() -> [SessionSnapshot] {
        let now = Date()
        return discovery.parseAll(modifiedWithin: watchWindow)
            .map { SessionSnapshot(
                session: $0.session,
                state: StateClassifier.classify(events: $0.events, now: now,
                                                thresholds: thresholds)) }
            .sorted { ($0.session.lastEventAt ?? .distantPast)
                    > ($1.session.lastEventAt ?? .distantPast) }
    }
}
