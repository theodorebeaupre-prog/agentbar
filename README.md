# AgentBar

[![CI](https://github.com/theodorebeaupre-prog/agentbar/actions/workflows/ci.yml/badge.svg)](https://github.com/theodorebeaupre-prog/agentbar/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Mission control for your coding agents. Native, free, 100% local.**

You run three Claude Code sessions and a Codex session across four terminals.
One of them has been waiting for your answer for 20 minutes. AgentBar is the
macOS menu bar app that makes that impossible:

![AgentBar demo — live session status in the menu bar, waiting sessions pinned on top](docs/demo.gif)

> 🛠️ Shipping solo with AI? The **Ship Kit** packs 3 premium Claude Code skills, proven config templates, and a zero-budget launch playbook → https://isonord.gumroad.com/l/qblnuh

- ⚡ **Live status** of every Claude Code / Codex session — working, waiting
  for you, idle — straight from the menu bar
- 🔔 **Native notification** the moment an agent needs your input
- 💬 **Reply from the bar** — answer a waiting Claude Code session in place.
  AgentBar resumes it through your **local `claude` CLI** — no API key, no
  copy-pasting back to a terminal
- ✨ **Ask Claude** — a quick chat box in the menu bar for one-off questions,
  answers streaming in live
- ⏪ **Session replay** — browse past sessions as a timeline: prompts, tool
  calls, files touched
- 🛡 **Skill & MCP audit** — heuristic scan of everything you've installed:
  exfiltration patterns, dangerous commands, injection language, unpinned
  sources — now with an optional **AI review** that reads it all in plain
  English. *(No flags ≠ guaranteed safe — rules are heuristic and every
  finding shows you exactly why.)*
- 🔒 **Local by design** — monitoring, replay, and the heuristic audit read
  local files only and make **zero network calls**; AgentBar never writes to
  `~/.claude` or `~/.codex`. Reply / Ask / AI-review shell out to the `claude`
  command *you* already installed and logged into — no API key lives in
  AgentBar, and the CLI uses its own credentials

## Install

Requires macOS 14 (Sonoma) or later.

```sh
brew install --cask theodorebeaupre-prog/tap/agentbar
```

Or build from source:

```sh
git clone https://github.com/theodorebeaupre-prog/agentbar.git
cd agentbar
swift build -c release            # CLI → .build/release/agentbar
cd App && xcodegen && xcodebuild -scheme AgentBar -configuration Release build
```

## CLI

One cask installs both the app and the `agentbar` CLI:

```sh
agentbar                    # status table of all current sessions (default)
agentbar watch              # live-updating status, Ctrl-C to exit
agentbar replay             # timeline of the most recent session; --json for scripting
agentbar audit              # scan installed skills/MCP configs; exits 1 on red findings
agentbar ask "why is CI red?"   # one-off question via your local `claude` CLI
agentbar reply 0 "yes, ship it" # resume a session by index and send a text reply
agentbar audit --ai         # heuristic scan + a natural-language review from Claude
```

`agentbar audit` is CI-friendly: wire it into a pipeline and fail the build
when a red finding appears.

`ask`, `reply`, and `audit --ai` drive the `claude` binary already on your
`PATH` (override with `AGENTBAR_CLAUDE_BIN`) — there is no API key and no
network code in AgentBar itself. `reply` defaults to `--permission-mode
acceptEdits`; pass `--permission-mode plan` for a dry run or
`bypassPermissions` to let it run freely.

## How state detection works

AgentBar tails the JSONL transcripts both CLIs already write
(`~/.claude/projects/`, `~/.codex/sessions/`). A session whose last event is a
finished assistant turn is *waiting for you*; recent tool activity means
*working*; silence means *idle*. Zero configuration, no hooks, no wrappers —
and if the transcript format drifts, unknown records degrade gracefully
instead of breaking. This is heuristic, not exact: a session blocked on a
permission prompt currently reads as *working*, and a finished-but-closed
session reads as *waiting* until the idle gate kicks in. A precise
hook-based signal is planned for v0.2.

## License

MIT — © 2026 ISO NORD CA
