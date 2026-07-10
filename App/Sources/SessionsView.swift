import SwiftUI
import AgentKit

struct SessionsView: View {
    @State private var parsed: [ParsedSession] = []
    @State private var selected: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var isLoading = true

    var body: some View {
        HSplitView {
            Group {
                if isLoading {
                    ProgressView("Indexing session history…")
                        .frame(minWidth: 220, maxWidth: 300, maxHeight: .infinity)
                } else {
                    List(parsed, id: \.session.id, selection: $selected) { p in
                        VStack(alignment: .leading) {
                            Text(p.session.projectName).fontWeight(.medium)
                            Text(p.session.title ?? p.session.provider.displayName)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(TextRendering.relative(p.session.lastEventAt))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }.tag(p.session.id)
                    }.frame(minWidth: 220, maxWidth: 300)
                }
            }

            ScrollView {
                if let p = parsed.first(where: { $0.session.id == selected }) {
                    Text(TextRendering.timelineText(ReplayBuilder.timeline(from: p.events)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                } else {
                    ContentUnavailableView("Select a session", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            // parseAll(modifiedWithin: nil) walks every history file on disk and can
            // take minutes on a machine with a large session history. Running it
            // directly in this closure risks executing on the main actor (SwiftUI
            // does not guarantee `.task` bodies run off-main, and @State mutation
            // is expected to happen on the main actor), which would beachball the
            // UI for the duration of the parse. Do the heavy synchronous work in a
            // detached, non-actor-isolated task, then hop back to the main actor
            // only to publish the result.
            //
            // Guard against re-selecting the Sessions tab (which spawns a fresh
            // view identity and re-runs `.task`) stacking a second multi-minute
            // scan on top of one already in flight.
            guard loadTask == nil else { return }
            loadTask = Task.detached(priority: .userInitiated) {
                let sorted = SessionDiscovery().parseAll(modifiedWithin: nil)
                    .sorted { ($0.session.lastEventAt ?? .distantPast)
                            > ($1.session.lastEventAt ?? .distantPast) }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    parsed = sorted
                    isLoading = false
                }
            }
            await loadTask?.value
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}
