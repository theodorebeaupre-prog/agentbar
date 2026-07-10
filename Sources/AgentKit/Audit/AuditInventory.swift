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
        for rel in [".claude/settings.json", ".claude/settings.local.json"] {
            let settings = home.appendingPathComponent(rel)
            if let content = try? String(contentsOf: settings, encoding: .utf8) {
                items.append(AuditItem(name: rel, kind: .hook,
                                       sourcePath: settings.path, content: content))
            }
        }
        return items
    }

    /// Enumerates SKILL.md files under `root`. Passes an explicit errorHandler
    /// that skips unreadable entries and keeps walking, rather than letting the
    /// default (nil) behavior silently abort the remaining traversal: an audit
    /// reports what it CAN see, not a truncated view masquerading as complete.
    private func skillItems(under root: URL, namePrefix: String) -> [AuditItem] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true })
        else { return [] }
        var out: [AuditItem] = []
        for case let url as URL in e {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let dir = url.deletingLastPathComponent()
            let name = namePrefix.isEmpty
                ? dir.lastPathComponent
                : namePrefix + pluginSkillName(dir: dir, root: root)
            out.append(AuditItem(name: name, kind: .skill,
                                 sourcePath: url.path, content: content))
        }
        return out
    }

    /// Names a plugin skill `<plugin>/<skill-dir-name>` so that skills with the
    /// same directory name in different plugins don't collide and the plugin
    /// identity is preserved. Computed from the SKILL.md directory's path
    /// relative to the enumeration root (the plugin cache dir).
    ///
    /// The cache layout is `<marketplace>/<plugin>/<version>/skills/<skill>`,
    /// so when a `skills` component is present, the plugin id is the component
    /// two before it (the component immediately before `skills` is the version
    /// directory). Unknown/shallower layouts fall back to joining every
    /// relative directory component with "/" — not as readable, but always
    /// unambiguous.
    private func pluginSkillName(dir: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let dirComponents = dir.standardizedFileURL.pathComponents
        let relative = Array(dirComponents.dropFirst(rootComponents.count))
        if let skillsIndex = relative.firstIndex(of: "skills"),
           skillsIndex >= 2,
           let skillDirName = relative.last {
            let plugin = relative[skillsIndex - 2]
            return "\(plugin)/\(skillDirName)"
        }
        return relative.joined(separator: "/")
    }
}
