# AgentBar — Design Spec

**Date:** 2026-07-10
**Status:** Approved for planning
**Author:** Théodore Beaupré (with Claude Code)

## One-liner

> **Mission control for your coding agents. Native, free, 100% local.**

A macOS menu bar app + CLI that tells you at a glance: which agent sessions are
working, which are **waiting for your input**, what happened in past sessions,
and what your installed skills/MCP servers are actually allowed to do.

## Problem

Developers run 3–5 Claude Code / Codex sessions in parallel across terminals
and forget them. An agent blocked on a question can sit idle for 20 minutes
before anyone notices. Meanwhile, people install dozens of third-party skills
and MCP servers without reading them. There is no native, zero-config tool
that watches all of this.

## Positioning & viral loop

- Same formula as PhotoCull: **free + native + on-device** vs. the ecosystem's
  default of Electron dashboards and cloud telemetry.
- The audience (Claude Code / Codex power users) *is* the GitHub/HN audience —
  shortest possible viral loop.
- README sells with one GIF: menu bar badge flips from `2 working` to
  `1 waiting for you`, native notification fires, user clicks, answers, agent
  resumes.
- Secondary hook (audit): "You installed 40 skills. Do you know what they can
  do?"

## Goals (v0.1)

1. **Live monitor (hero):** real-time state of every local agent session, with
   a native notification the moment a session starts waiting for user input.
2. **Sessions & replay (minimal):** browsable history of past sessions with a
   chronological textual timeline (prompts, tools called, files touched).
3. **Audit (minimal):** heuristic scan of installed skills, plugins, and MCP
   configs with flagged findings and honest explanations.
4. Ship both a **CLI** (`agentbar`) and a **menu bar app** from one shared
   Swift core, installable via `brew install --cask`.

## Non-goals (v0.1)

- No writes to `~/.claude` or `~/.codex` — strictly read-only, ever.
- No network calls, no telemetry, no accounts (non-negotiable, it's the brand).
- No token-cost accounting/analytics (ccusage territory; maybe v0.2).
- No control of sessions (no sending input to agents, no kill/restart).
- No sandboxed / Mac App Store distribution (needs broad home-dir reads).
- Not an antivirus: audit is heuristic and explains itself; it never claims a
  skill is "safe", only that nothing was flagged.
- No Windows/Linux (native macOS is the differentiator; CLI is portable-ish by
  design but untested elsewhere).

## Data sources (verified on-machine 2026-07-10)

### Claude Code

- Sessions: `~/.claude/projects/<escaped-cwd>/<session-uuid>.jsonl`
- One JSON object per line. Observed event `type`s: `user`, `assistant`,
  `attachment`, `system`, `queue-operation`, `last-prompt`, `custom-title`.
- Useful fields: `type`, `timestamp` (ISO 8601), `sessionId`, `cwd`,
  `gitBranch`, `version`, `message` (role + content array, incl. `tool_use` /
  `tool_result` blocks), `customTitle`.
- Skills: `~/.claude/skills/<name>/SKILL.md` (+ user/project variants).
- Plugins: `~/.claude/plugins/cache/...` (each plugin ships skills/commands).
- MCP configs: `~/.claude.json` (global), project `.mcp.json`,
  `.claude/settings*.json`.

### Codex

- Sessions: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`
- First line is `session_meta` with `payload`: `session_id`, `cwd`,
  `originator`, `cli_version`, `source`, `model_provider`.
- Subsequent lines: timestamped typed events (schema to be mapped precisely
  during implementation; state detection uses the same recency heuristics).
- Config: `~/.codex/config.toml` (MCP servers section, if present).

### Format-drift stance

Both formats are undocumented internals and WILL drift. AgentKit treats every
record as `[String: JSONValue]`, extracts only the fields it needs, and maps
anything unrecognized to `.unknown` states rather than failing. Parser fixtures
pin the formats observed today; a drift is a failing fixture test, not a crash.

## Architecture

Mono-repo, one Swift core, two consumers:

```
AgentBar/
├── Packages/AgentKit/            SwiftPM package — all logic, zero UI
│   ├── Sources/AgentKit/
│   │   ├── Model/                Session, SessionEvent, SessionState,
│   │   │                         Provider (claudeCode | codex), Finding
│   │   ├── Discovery/            locate session files per provider
│   │   ├── Parsing/              tolerant JSONL readers (one per provider)
│   │   ├── Watching/             SessionWatcher: DispatchSource file/dir
│   │   │                         watchers + state machine + debounce
│   │   ├── Replay/               timeline builder from parsed events
│   │   └── Audit/                rule engine + built-in rule set
│   └── Tests/AgentKitTests/      fixtures = real anonymized JSONL snippets
├── Sources/agentbar-cli/         swift-argument-parser executable
├── App/                          SwiftUI MenuBarExtra app (xcodegen project.yml,
│                                 same toolchain/pipeline as PhotoCull)
├── docs/
└── .github/workflows/            build + test + release (cask publish, reuse
                                  PhotoCull release pipeline)
```

**Dependency rule:** App and CLI depend on AgentKit. AgentKit depends on
Foundation only (plus swift-argument-parser for the CLI target). No third-party
runtime deps in AgentKit — keeps audit surface ironic-free.

## Session state machine

States per session:

| State | Meaning | Heuristic |
|---|---|---|
| `working` | Agent is producing output / running tools | Last event age < *activeThreshold* (default 30 s), OR last event is `assistant` containing `tool_use` |
| `waitingForInput` | Turn ended, user's move | Last meaningful event is a completed `assistant` message with no pending `tool_use`, and file quiet for > *settleDelay* (default 5 s). AskUserQuestion tool_use detected in last assistant message → immediate `waitingForInput` |
| `idle` | Session open but stale | No events for > *idleThreshold* (default 30 min) |
| `ended` | Session closed | Summary/terminal marker observed, or no events for > *endedThreshold* (default 24 h) |
| `unknown` | Unparseable tail | Parser couldn't classify — displayed, never hidden |

Transitions are recomputed on every file-system event (debounced 500 ms) and on
a 15 s safety timer. Thresholds are constants in v0.1 (config file is v0.2).

**Notification policy:** fire exactly one native notification per
`* → waitingForInput` transition per session, with a per-session cooldown
(default 60 s) so rapid-fire turns don't spam. Clicking the notification opens
the app's Live view. Notifications require user authorization on first launch;
denial degrades gracefully to badge-only.

## Component specs

### AgentKit.SessionStore

- `discoverSessions() -> [Session]` — scan both providers' directories.
- `events(for: Session) -> AsyncThrowingStream<SessionEvent, Error>` — lazy
  parse; tolerant reader skips malformed lines (kept count surfaced in debug).
- Session identity = provider + file path; metadata = title (customTitle or
  first prompt truncated), cwd, git branch, start/last-event timestamps.

### AgentKit.SessionWatcher

- Watches provider root dirs for new files + active session files for appends.
- Emits `SessionSnapshot` (session + state + lastEvent) via AsyncStream;
  consumers (App, `agentbar watch`) render it.
- Only tails files modified in the last 48 h; older files are history, not
  watch candidates (bounds file-descriptor usage).

### AgentKit.Replay

- Input: parsed events of one session. Output: `[TimelineEntry]` —
  `prompt(text)`, `response(summary)`, `toolCall(name, target)`,
  `fileTouched(path, kind)`, `notable(marker)` — each with timestamp and
  elapsed-since-previous.
- File touches derived from tool_use blocks (Edit/Write/NotebookEdit args).
- v0.1 rendering is plain chronological text (CLI) / simple list (App).

### AgentKit.Audit

- Inventory: skills (user + plugin-provided), MCP server configs, hooks in
  settings files.
- Rule engine: `AuditRule { id, severity, title, matcher, explanation }`
  running over SKILL.md bodies, command definitions, hook commands, and MCP
  server launch commands.
- v0.1 built-in rules (each finding shows the matched excerpt + why it
  matters):
  - `net-exfil` 🔴 — curl/wget/fetch to non-localhost URLs inside skill
    instructions or hooks
  - `shell-danger` 🔴 — `rm -rf`, `sudo`, piping remote scripts to sh,
    credential-file reads (`~/.ssh`, `~/.aws`, keychain access)
  - `injection-language` 🔴 — instructions directing the agent to ignore/
    override user or system instructions, hide actions, or suppress output
  - `broad-permissions` 🟡 — hooks or MCP servers launched with wide
    filesystem scope; `Bash(*)`-style allowlist entries in settings
  - `obfuscation` 🟡 — base64 blobs / hex-encoded commands inside instructions
  - `unpinned-source` 🟡 — MCP servers run via `npx <pkg>@latest` or raw
    `curl | sh` installers
- Output: findings grouped per item, severity-sorted; explicit "0 flags ≠
  guaranteed safe" disclaimer in both UIs.

### CLI (`agentbar`)

- `agentbar status` — table of current sessions + states (the default command).
- `agentbar watch` — live-updating status (simple redraw loop), Ctrl-C to exit.
- `agentbar replay [<session-id|index>]` — timeline of a session (most recent
  if omitted); `--json` for scripting.
- `agentbar audit` — run rules, print findings; exit code 1 if any 🔴 (CI-able).
- Distribution: bundled inside the app (`AgentBar.app/Contents/MacOS/agentbar`
  symlinked by the cask as a binary stanza), so one cask installs both.

### App (menu bar)

- `MenuBarExtra` with dynamic label: glyph + count of `waitingForInput`
  sessions (badge hidden at 0; subtle animation on transition).
- Menu content: session rows (state dot, project name, title, relative time);
  clicking a row opens the main window on that session.
- Main window, 3 sidebar sections:
  1. **Live** — active sessions, richer cards, "waiting" sessions pinned top.
  2. **Sessions** — history grouped by project; detail = replay timeline.
  3. **Audit** — inventory table with severity flags; detail = findings with
     excerpts and explanations; "Rescan" button.
- Launch-at-login toggle (SMAppService). No dock icon (LSUIElement).

## Error handling

- All reads are failable-and-degradable: a provider dir missing → provider
  silently absent; a file unreadable → session listed as `unknown` with a
  tooltip; a malformed line → skipped and counted.
- The app must never crash on foreign data. Fuzz-ish test: parser fed truncated
  and shuffled fixture lines must produce states, not throws.
- Full-disk-access is NOT required (home-dir dotfiles are readable), but if a
  read is denied the UI says exactly which path and why it matters.

## Testing

- **AgentKitTests** (the real coverage): state machine transition table tests;
  parser fixture tests per provider (real anonymized JSONL, including a
  malformed-lines fixture); audit rule tests with true-positive AND
  false-positive fixtures per rule (a rule without a false-positive test
  doesn't ship); replay timeline golden tests.
- **CLI smoke test** in CI: run `status`/`audit` against fixture HOME.
- App UI: manual test checklist in `docs/testing.md` (menu bar states,
  notification flow, permission-denied path).

## Distribution & launch

- MIT license. `brew install --cask theodorebeaupre-prog/tap/agentbar`
  (reuse PhotoCull's tap + GitHub Actions release pipeline: build, sign,
  notarize, cask PR).
- README: hero GIF (badge flip + notification), 3-bullet pitch, install
  one-liner, honest audit disclaimer, "how state detection works" section
  (transparency reads as trustworthy and is HN-comment bait in the good way).
- Launch checklist: GIF recorded with comotion/ffmpeg, Show HN post, r/ClaudeAI
  + r/LocalLLaMA posts, tweet thread.

## Naming

Working name **AgentBar** (descriptive: agents + menu bar). Rename before
first push is trivial; alternatives parked: overwatch (taken by Blizzard,
avoid), agentdeck, shepherd.

## Roadmap (post-v0.1, parked)

- v0.2: token/cost stats per session; configurable thresholds; hook-based
  precise state signal (optional, still zero-config by default); more
  providers (Gemini CLI, OpenCode); shareable HTML replay export.
- v0.3: audit rule packs updatable from the repo (still offline-first).
