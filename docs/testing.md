# Manual test checklist (App)

Run before every release. AgentKit logic is covered by `swift test`;
this list covers what only a human can see.

## Menu bar
- [ ] Icon appears; no Dock icon
- [ ] Badge shows count only when ≥1 session is waiting
- [ ] Rows sorted: waiting first, then by recency
- [ ] "Open AgentBar" opens the main window; "Quit" quits

## Notifications
- [ ] First launch asks for permission
- [ ] Agent finishing a turn triggers exactly one notification (≤15 s delay)
- [ ] Answering and re-finishing within 60 s does NOT re-notify (cooldown)
- [ ] With permission denied: no crash, badge still updates
- [ ] With the menu popover CLOSED, clicking a notification opens the main window (label-view wiring)

## Sessions
- [ ] History lists real sessions, newest first
- [ ] Timeline shows prompts/tools/files, text selectable

## Audit
- [ ] Real machine scan completes < 5 s, findings show excerpt + explanation
- [ ] Disclaimer visible in both empty and non-empty states

## Robustness
- [ ] `echo 'garbage' >> <an active session .jsonl copy in a fake HOME>` → no crash
- [ ] Quit + relaunch: state re-detected correctly
