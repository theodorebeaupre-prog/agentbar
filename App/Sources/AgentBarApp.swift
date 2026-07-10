import SwiftUI
import AgentKit

@main
struct AgentBarApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            LiveMenuContent(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("AgentBar", id: "main") {
            MainWindow(store: store)
        }
    }
}

/// The MenuBarExtra label view stays resident in the menu bar for the app's
/// entire lifetime, unlike the MenuBarExtra *content* (`LiveMenuContent`),
/// which SwiftUI may tear down while the popover is closed. Notification
/// clicks happen precisely when the popover is closed, so the
/// `.agentBarOpenMainWindow` subscription lives here to guarantee it fires.
struct MenuBarLabel: View {
    @ObservedObject var store: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.waitingCount > 0 {
                Label("\(store.waitingCount)", systemImage: "bolt.badge.clock")
            } else {
                Image(systemName: "bolt")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentBarOpenMainWindow)) { _ in
            openWindow(id: "main")
        }
    }
}
