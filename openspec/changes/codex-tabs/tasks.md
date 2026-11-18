## 1. Build
- [ ] 1.0 On one throwaway tab: the SessionStart hook sees the tab's tty and a `codex` process above it; what `/new` does to the pid and the thread id; which process holds the rollout file; whether the state database can be read while Codex runs. If the hook cannot see the tty, stop and bring the design back to the owner
- [x] 1.1 Codex SessionStart hook writes `.local/codex-threads/<tty>` (mode 600) from the `session_id` of the hook's JSON input, with the pid of the nearest `codex` ancestor on that tty; must-fail: no tty, no `codex` ancestor, id not a UUID
- [x] 1.2 sessions.sh maps a Codex tab to its id only per HOME-327; must-fail fixtures: dead pid, other pid on the tty, missing rollout, a newer `cli` thread in the same cwd, archived row
- [x] 1.3 HOME-055 lets survey, state, park, resume, send and close run in a Codex session; open, freeze and thaw still exit 3 (fixtures both ways)
- [x] 1.4 park and resume of a mapped Codex tab with `codex resume <id>` on the fake backend
- [ ] 1.5 Real-tab check (HOME-329) on throwaway tabs; record the screen markers of a Codex tab (input box, running turn, dialog), the exit command and whether `codex resume` keeps the same id
- [x] 1.6 orchestrate section 9 and the README tool table say which verbs drive Codex tabs
