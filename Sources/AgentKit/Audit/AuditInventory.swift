import Foundation

/// Collects auditable text from the user's agent setup. Read-only; any
/// unreadable path is silently skipped (audit reports what it CAN see).
public struct AuditInventory {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func collect() -> [AuditItem] {
        var items: [AuditItem] = []
        items += skillItems(under: home.appendingPathComponent(".claude/skills"),
                            namePrefix: "")
        items += skillItems(under: home.appendingPathComponent(".claude/plugins/cache"),
                            namePrefix: "plugin:")
        for rel in [".claude.json", ".codex/config.toml"] {
            let url = home.appendingPathComponent(rel)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                items.append(AuditItem(name: rel, kind: .mcpServer,
                                       sourcePath: url.path, content: content))
            }
        }
        let settings = home.appendingPathComponent(".claude/settings.json")
        if let content = try? String(contentsOf: settings, encoding: .utf8) {
            items.append(AuditItem(name: ".claude/settings.json", kind: .hook,
                                   sourcePath: settings.path, content: content))
        }
        return items
    }

    private func skillItems(under root: URL, namePrefix: String) -> [AuditItem] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var out: [AuditItem] = []
        for case let url as URL in e {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = namePrefix + url.deletingLastPathComponent().lastPathComponent
            out.append(AuditItem(name: name, kind: .skill,
                                 sourcePath: url.path, content: content))
        }
        return out
    }
}
