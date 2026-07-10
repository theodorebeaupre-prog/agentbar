import SwiftUI
import AgentKit

@main
struct AgentBarApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            LiveMenuContent(store: store)
        } label: {
            if store.waitingCount > 0 {
                Label("\(store.waitingCount)", systemImage: "bolt.badge.clock")
            } else {
                Image(systemName: "bolt")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
