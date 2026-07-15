import SwiftUI
import AgentKit

/// Quick chat with the local `claude` CLI, straight from the menu bar app.
/// Read-only by default (no file edits) — it's for questions, not tasks.
struct AskView: View {
    @StateObject private var runner = ClaudeRunner()

    var body: some View {
        VStack(spacing: 0) {
            if runner.isAvailable {
                HStack {
                    Label("Ask Claude", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if !runner.turns.isEmpty {
                        Button("New chat") { runner.reset() }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                ChatPanel(runner: runner,
                          placeholder: "Ask Claude anything…",
                          mode: .default,
                          emptyHint: "Ask Claude Code a question.\nRuns your local `claude` command — no API key. Answers stream in below.")
            } else {
                ClaudeUnavailableView()
            }
        }
    }
}
