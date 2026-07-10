import SwiftUI
import AgentKit

struct AuditView: View {
    @State private var items: [AuditItem] = []
    @State private var findings: [AuditFinding] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scanned \(items.count) items — \(findings.count) findings")
                    .font(.headline)
                Spacer()
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
    }

    private func scan() {
        items = AuditInventory().collect()
        findings = AuditEngine.scan(items)
    }
}
