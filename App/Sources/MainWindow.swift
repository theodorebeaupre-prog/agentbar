import SwiftUI
import ServiceManagement
import AgentKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case live = "Live", sessions = "Sessions", ask = "Ask", audit = "Audit"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .live: return "bolt"
        case .sessions: return "clock.arrow.circlepath"
        case .ask: return "sparkles"
        case .audit: return "checkmark.shield"
        }
    }
}

struct MainWindow: View {
    @ObservedObject var store: SessionStore
    @State private var selection: SidebarItem = .live
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .safeAreaInset(edge: .bottom) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox).font(.caption).padding(8)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register()
                                : SMAppService.mainApp.unregister()
                    }
            }
        } detail: {
            switch selection {
            case .live: LiveDetail(store: store)
            case .sessions: SessionsView()
            case .ask: AskView()
            case .audit: AuditView()
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(for: .agentBarShowAsk)) { _ in
            selection = .ask
        }
    }
}

struct LiveDetail: View {
    @ObservedObject var store: SessionStore
    @State private var replyTarget: Session?

    var body: some View {
        List(store.snapshots, id: \.session.id) { snap in
            HStack(spacing: 8) {
                SessionRow(snapshot: snap)
                if snap.session.provider == .claudeCode, snap.session.resumeID != nil {
                    Button {
                        replyTarget = snap.session
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Reply to this session with Claude Code")
                }
            }
        }
        .overlay {
            if store.snapshots.isEmpty {
                ContentUnavailableView("No recent sessions",
                    systemImage: "bolt.slash",
                    description: Text("Start a Claude Code or Codex session and it will appear here."))
            }
        }
        .sheet(item: $replyTarget) { SessionReplyView(session: $0) }
    }
}
