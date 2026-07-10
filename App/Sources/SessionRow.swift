import SwiftUI
import AgentKit

struct SessionRow: View {
    let snapshot: SessionSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.session.projectName).font(.system(.body, weight: .medium))
                Text(snapshot.session.title ?? snapshot.session.provider.displayName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(TextRendering.relative(snapshot.session.lastEventAt))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    var color: Color {
        switch snapshot.state {
        case .working: return .green
        case .waitingForInput: return .orange
        case .idle: return .gray
        case .ended: return .gray.opacity(0.4)
        case .unknown: return .purple
        }
    }
}
