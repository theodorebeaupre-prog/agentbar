import SwiftUI
import AgentKit

/// One conversational turn shown in a chat/reply transcript.
struct ChatTurn: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var tools: [String] = []
    var footer: String?
    var isError = false
}

/// Drives a streaming conversation with the local `claude` CLI for the UI.
/// Owns a transcript that updates live as tokens arrive. A single runner keeps
/// one thread going: the first reply captures the session id, and every
/// subsequent send resumes it, so the panel behaves like a real chat.
@MainActor
final class ClaudeRunner: ObservableObject {
    @Published var turns: [ChatTurn] = []
    @Published var isRunning = false
    /// The live session id — seeded for a reply, then updated from the CLI.
    @Published private(set) var sessionID: String?

    let cli = ClaudeCLI()
    var isAvailable: Bool { cli.isAvailable }

    private let cwd: URL?
    private var task: Task<Void, Never>?

    init(resumeSessionID: String? = nil, cwd: URL? = nil) {
        self.sessionID = resumeSessionID
        self.cwd = cwd
    }

    /// Sends `prompt`, appending a user turn and a streaming assistant turn.
    func send(_ prompt: String, model: String? = nil,
              mode: ClaudePermissionMode = .default, showUserTurn: Bool = true) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }

        if showUserTurn { turns.append(ChatTurn(role: .user, text: text)) }
        turns.append(ChatTurn(role: .assistant, text: ""))
        let idx = turns.count - 1
        isRunning = true

        let req = ClaudeRequest(prompt: text, resumeSessionID: sessionID, cwd: cwd,
                                model: model, permissionMode: mode)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await ev in self.cli.stream(req) {
                    guard idx < self.turns.count else { break }
                    switch ev {
                    case .systemInit(let sid, _):
                        if let sid { self.sessionID = sid }
                    case .assistantText(let t):
                        self.turns[idx].text += t
                    case .toolUse(let name, let target):
                        self.turns[idx].tools.append(target.map { "\(name) · \($0)" } ?? name)
                    case .result(let r):
                        if let sid = r.sessionID { self.sessionID = sid }
                        self.turns[idx].footer = Self.footer(r)
                        self.turns[idx].isError = r.isError
                        if r.isError, self.turns[idx].text.isEmpty { self.turns[idx].text = r.text }
                    }
                }
            } catch {
                if idx < self.turns.count {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.turns[idx].isError = true
                    self.turns[idx].text = self.turns[idx].text.isEmpty
                        ? msg : self.turns[idx].text + "\n\n⚠️ " + msg
                }
            }
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Clears the transcript and drops the session id, starting a fresh thread.
    func reset() {
        cancel()
        turns = []
        sessionID = nil
    }

    private static func footer(_ r: ClaudeResult) -> String? {
        var bits: [String] = []
        if let c = r.costUSD { bits.append(String(format: "$%.4f", c)) }
        if let d = r.durationMS { bits.append(String(format: "%.1fs", Double(d) / 1000)) }
        if let n = r.numTurns { bits.append("\(n) turn\(n == 1 ? "" : "s")") }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
}

/// Shown when `claude` can't be located. Keeps the feature honest instead of
/// failing silently.
struct ClaudeUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Claude Code not found", systemImage: "terminal")
        } description: {
            Text("AgentBar drives your local `claude` command — no API key. Install Claude Code and make sure `claude` is on your PATH, then reopen this tab.")
        }
    }
}

/// A reusable chat transcript + input bar used by Ask and Reply.
struct ChatPanel: View {
    @ObservedObject var runner: ClaudeRunner
    var placeholder: String
    var mode: ClaudePermissionMode
    var emptyHint: String?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(runner.turns) { turn in
                            ChatBubble(turn: turn).id(turn.id)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay {
                    if runner.turns.isEmpty, let emptyHint {
                        Text(emptyHint)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(40)
                    }
                }
                .onChange(of: runner.turns.last?.text) { _, _ in
                    if let last = runner.turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(send)
                if runner.isRunning {
                    Button(role: .destructive) { runner.cancel() } label: {
                        Image(systemName: "stop.circle.fill")
                    }.buttonStyle(.borderless)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
        }
        .onAppear { focused = true }
    }

    private func send() {
        let text = draft
        draft = ""
        runner.send(text, mode: mode)
    }
}

private struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 4) {
                if !turn.tools.isEmpty {
                    ForEach(turn.tools, id: \.self) { t in
                        Label(t, systemImage: "wrench.and.screwdriver")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(displayText)
                    .textSelection(.enabled)
                    .foregroundStyle(turn.isError ? Color.red : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                if let footer = turn.footer {
                    Text(footer).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if turn.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var displayText: String {
        if turn.role == .assistant, turn.text.isEmpty, !turn.isError { return "…" }
        return turn.text
    }

    private var bubbleColor: Color {
        turn.role == .user ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12)
    }
}
