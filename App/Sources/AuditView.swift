import SwiftUI
import AgentKit

struct AuditView: View {
    @State private var items: [AuditItem] = []
    @State private var findings: [AuditFinding] = []
    @State private var showingAIReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scanned \(items.count) items — \(findings.count) findings")
                    .font(.headline)
                Spacer()
                Button {
                    showingAIReview = true
                } label: {
                    Label("AI Review", systemImage: "sparkles")
                }
                .help("Ask the local Claude Code CLI for a natural-language review")
                Button("Rescan") { scan() }
            }.padding()

            List {
                ForEach(findings, id: \.self) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(f.severity == .red ? "🔴" : "🟡")
                            Text(f.itemName).fontWeight(.medium)
                            Text("[\(f.ruleID)]").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(f.excerpt).font(.system(.caption, design: .monospaced))
                        Text(f.explanation).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }
            }
            .overlay {
                if findings.isEmpty {
                    ContentUnavailableView("No findings", systemImage: "checkmark.shield",
                        description: Text(AuditEngine.disclaimer))
                }
            }
            Text("⚠️ \(AuditEngine.disclaimer)")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .task { scan() }
        .sheet(isPresented: $showingAIReview) {
            AuditAIReviewView(items: items)
        }
    }

    private func scan() {
        items = AuditInventory().collect()
        findings = AuditEngine.scan(items)
    }
}

/// Streams a natural-language security review of the audited inventory from the
/// local `claude` CLI. Complements the heuristic rules with judgment — still
/// 100% local, no API key.
struct AuditAIReviewView: View {
    let items: [AuditItem]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = ClaudeRunner()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI Review", systemImage: "sparkles").font(.headline)
                Spacer()
                if runner.isRunning {
                    ProgressView().controlSize(.small).padding(.trailing, 4)
                } else if runner.isAvailable, !runner.turns.isEmpty {
                    Button("Re-run") { start() }
                }
                Button("Done") { dismiss() }
            }
            .padding(12)
            Divider()

            if !runner.isAvailable {
                ClaudeUnavailableView()
            } else {
                ScrollView {
                    let review = runner.turns.last(where: { $0.role == .assistant })
                    Text(review?.text.isEmpty == false ? review!.text : "Reviewing \(items.count) items…")
                        .foregroundStyle(review?.isError == true ? Color.red : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    if let footer = review?.footer {
                        Text(footer).font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    }
                }
                Divider()
                Text("⚠️ \(AuditEngine.disclaimer)")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .frame(width: 620, height: 560)
        .onAppear { if runner.turns.isEmpty { start() } }
    }

    private func start() {
        runner.reset()
        runner.send(ClaudePrompts.auditReview(items: items), mode: .plan, showUserTurn: false)
    }
}
