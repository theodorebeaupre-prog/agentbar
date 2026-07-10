# AgentBar

**Mission control for your coding agents. Native, free, 100% local.**

You run three Claude Code sessions and a Codex session across four terminals.
One of them has been waiting for your answer for 20 minutes. AgentBar is the
macOS menu bar app that makes that impossible:

![AgentBar demo](docs/demo.gif)

- ⚡ **Live status** of every Claude Code / Codex session — working, waiting
  for you, idle — straight from the menu bar
- 🔔 **Native notification** the moment an agent needs your input
- ⏪ **Session replay** — browse past sessions as a timeline: prompts, tool
  calls, files touched
- 🛡 **Skill & MCP audit** — heuristic scan of everything you've installed:
  exfiltration patterns, dangerous commands, injection language, unpinned
  sources. *(No flags ≠ guaranteed safe — rules are heuristic and every
  finding shows you exactly why.)*
- 🔒 **Private by design** — reads local files only; zero network calls, zero
  telemetry, never writes to `~/.claude` or `~/.codex`

## Install

```sh
brew install --cask theodorebeaupre-prog/tap/agentbar
```

Ships with a CLI too: `agentbar status | watch | replay | audit`.
`agentbar audit` exits 1 on red findings — CI-friendly.

## How state detection works

AgentBar tails the JSONL transcripts both CLIs already write
(`~/.claude/projects/`, `~/.codex/sessions/`). A session whose last event is a
finished assistant turn is *waiting for you*; recent tool activity means
*working*; silence means *idle*. Zero configuration, no hooks, no wrappers —
and if the transcript format drifts, unknown records degrade gracefully
instead of breaking.

## License

MIT — © 2026 Théodore Beaupré
