import SwiftUI
import AgentKit

struct LiveMenuContent: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.snapshots.isEmpty {
                Text("No agent sessions in the last 48h")
                    .foregroundStyle(.secondary).padding(12)
            } else {
                ForEach(sorted, id: \.session.id) { snap in
                    SessionRow(snapshot: snap)
                }
            }
            Divider()
            HStack {
                Text("AgentBar \(AgentKitInfo.version)").font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.font(.caption)
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .frame(width: 340)
    }

    /// Waiting sessions pinned to the top (spec).
    var sorted: [SessionSnapshot] {
        store.snapshots.sorted {
            ($0.state == .waitingForInput ? 0 : 1, $1.session.lastEventAt ?? .distantPast)
          < ($1.state == .waitingForInput ? 0 : 1, $0.session.lastEventAt ?? .distantPast)
        }
    }
}
