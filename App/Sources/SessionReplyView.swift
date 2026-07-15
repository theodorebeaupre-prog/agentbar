import SwiftUI
import AgentKit

/// A sheet that sends a text reply into an existing Claude Code session by
/// resuming it through the local `claude` CLI. This is the app's controller
/// surface — the point where AgentBar stops merely watching and can act.
struct SessionReplyView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner: ClaudeRunner
    @State private var mode: ClaudePermissionMode = .acceptEdits

    init(session: Session) {
        self.session = session
        _runner = StateObject(wrappedValue: ClaudeRunner(
            resumeSessionID: session.resumeID,
            cwd: session.cwd.map { URL(fileURLWithPath: $0) }))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if runner.isAvailable {
                ChatPanel(runner: runner,
                          placeholder: "Reply to this session…",
                          mode: mode,
                          emptyHint: "Type a reply and Claude Code will resume this session in \(session.projectName).")
            } else {
                ClaudeUnavailableView()
            }
        }
        .frame(width: 560, height: 520)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reply · \(session.projectName)").font(.headline)
                Text(session.title ?? session.provider.displayName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker("", selection: $mode) {
                ForEach(ClaudePermissionMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            .help(mode.explanation)
            Button("Done") { dismiss() }
        }
        .padding(12)
    }
}
