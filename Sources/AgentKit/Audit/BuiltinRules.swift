import Foundation

extension AuditEngine {
    public static let builtinRules: [AuditRule] = [
        AuditRule(
            id: "net-exfil", severity: .red,
            title: "Sends data to a remote host",
            explanation: "Instructions tell the agent to POST/upload data to a non-local URL. Combined with file reads this is an exfiltration path.",
            patterns: [
                #"(curl|wget)\s+[^\n|;]*(-X\s*POST|--data|-d\s|--upload-file|-T\s)[^\n]*https?://(?!localhost|127\.0\.0\.1|0\.0\.0\.0)"#,
                #"(curl|wget)\s+[^\n]*https?://(?!localhost|127\.0\.0\.1|0\.0\.0\.0)[^\n]*(-d\s*@|--data\s*@)"#,
            ],
            appliesTo: nil),
        AuditRule(
            id: "shell-danger", severity: .red,
            title: "Dangerous shell command",
            explanation: "Destructive deletes outside the project, sudo, piping remote scripts to a shell, or reads of credential files (~/.ssh, ~/.aws, keychain).",
            patterns: [
                #"rm\s+-rf\s+(~|/Users|/home|\$HOME)"#,
                #"\bsudo\b"#,
                #"curl[^\n]*\|\s*(ba|z)?sh"#,
                #"~/\.(ssh|aws|gnupg)\b"#,
                #"security\s+find-generic-password"#,
            ],
            appliesTo: nil),
        AuditRule(
            id: "injection-language", severity: .red,
            title: "Instruction-override language",
            explanation: "Text that directs the agent to ignore prior instructions or hide its actions from the user — the signature of prompt injection.",
            patterns: [
                #"ignore\s+(all\s+|any\s+)?(previous|prior|above|system|user)('|’)?s?\s+instructions"#,
                #"do\s+not\s+(tell|inform|mention\s+to|reveal\s+to|alert)\s+the\s+user"#,
                #"without\s+(telling|informing|asking)\s+the\s+user"#,
                #"hide\s+(this|these|the)\s+(action|step|command)"#,
            ],
            appliesTo: nil),
        AuditRule(
            id: "broad-permissions", severity: .yellow,
            title: "Overly broad permission grant",
            explanation: "A wildcard allowlist entry grants unrestricted execution. Prefer scoped entries.",
            patterns: [
                #""allow"\s*:\s*\[[^\]]*"(Bash\(\*\)|\*)""#,
                #"Bash\(\*(:\*)?\)"#,
            ],
            appliesTo: nil),
        AuditRule(
            id: "obfuscation", severity: .yellow,
            title: "Obfuscated payload",
            explanation: "A long base64/hex blob inside instructions can hide commands from review, especially when piped to a decoder or shell.",
            patterns: [
                #"[A-Za-z0-9+/]{120,}={0,2}"#,
                #"(\\x[0-9a-fA-F]{2}){12,}"#,
            ],
            appliesTo: nil),
        AuditRule(
            id: "unpinned-source", severity: .yellow,
            title: "Unpinned remote code source",
            explanation: "Running a package at @latest (or a raw installer) means the code you audited today is not the code that runs tomorrow.",
            patterns: [
                #"npx[^\n]*\S@latest"#,
                #""args"\s*:\s*\[[^\]]*@latest"#,
            ],
            appliesTo: nil),
    ]
}
