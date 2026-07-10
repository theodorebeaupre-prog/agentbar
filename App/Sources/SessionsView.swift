import SwiftUI
import AgentKit

struct SessionsView: View {
    @State private var parsed: [ParsedSession] = []
    @State private var selected: String?

    var body: some View {
        HSplitView {
            List(parsed, id: \.session.id, selection: $selected) { p in
                VStack(alignment: .leading) {
                    Text(p.session.projectName).fontWeight(.medium)
                    Text(p.session.title ?? p.session.provider.displayName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(TextRendering.relative(p.session.lastEventAt))
                        .font(.caption2).foregroundStyle(.tertiary)
                }.tag(p.session.id)
            }.frame(minWidth: 220, maxWidth: 300)

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
            let sorted = await Task.detached(priority: .userInitiated) { () -> [ParsedSession] in
                SessionDiscovery().parseAll(modifiedWithin: nil)
                    .sorted { ($0.session.lastEventAt ?? .distantPast)
                            > ($1.session.lastEventAt ?? .distantPast) }
            }.value
            await MainActor.run { parsed = sorted }
        }
    }
}
