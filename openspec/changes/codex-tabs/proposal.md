## Why
Codex is meant to work a home the way Claude Code does, but the terminal helpers drive Claude Code tabs only: HOME-055 makes every verb exit 3 in a Codex session, and HOME-321 lists a Codex tab with no session id, so a Codex worker cannot be parked or resumed and a Codex orchestrator cannot read or park tabs.

Facts seen so far (read only, codex-cli 0.164; earlier Codex hook runs):
- `codex resume <id>` takes the thread id (a UUID); there is no launch flag that sets the id up front, so the `--session-id` way of Claude Code has no equal.
- A Codex hook does not get `CODEX_THREAD_ID` in its environment, but its JSON input's `session_id` equals the thread id; the commands Codex runs do get `CODEX_THREAD_ID`.
- The thread's rollout file is `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, and `~/.codex/state_5.sqlite` (table `threads`: id, cwd, source, rollout_path, created_at, updated_at, archived) maps ids to folders.

Not seen yet, so the real-tab check proves them (tasks 1.0 and 1.5): that the SessionStart hook of a terminal session runs with that session's tty above it; whether `/new` keeps the process and starts a new thread; which process holds a terminal session's rollout file open; and whether `codex resume <id>` keeps the same id.

Also not seen: the screen of a Codex tab. The helpers read a Codex tab with the readers they have (built for Claude Code's screen) and refuse when they find no input box; the real-tab check names the Codex markers and confirms or corrects the exit command (`/quit`, one constant in `term.sh`).

So the id comes from inside the session: the Codex SessionStart hook records it per tty, and the helpers trust that record only when it still matches the live tab. Known limit: when two Codex tabs work in one folder, the newer-thread rule leaves the older one unmapped (listed only, never closed); that fails safe.

## What Changes
- HOME-055: in a Codex session or with `launch.command=codex`, only `open`, `freeze` and `thaw` exit 3; `survey`, `state`, `park`, `resume`, `send` and `close` work.
- New HOME-326: the Codex SessionStart hook records the thread id, the pid of the `codex` process on its tty, the cwd and the time under `.local/codex-threads/`.
- New HOME-327: a Codex tab has a thread id only when that record matches the live tab and nothing newer contradicts it; otherwise it is listed only, never closed (HOME-322).
- New HOME-328: park and resume of a mapped Codex tab, with `cd <cwd> && codex resume <id>` as its resume line.
- New HOME-329: a real-tab check on throwaway tabs before any Codex tab of the owner is parked or closed. `open` stays Claude-only, so the check starts its Codex tabs itself (a new tab in the sandbox home, `codex` typed by the check), outside `term.sh open`.
- HOME-321: a mapped Codex tab shows its id and resume line.
- Freeze and thaw stay Claude-only (HOME-309 unchanged); `open` of a Codex tab is a later change.

## Impact
- `scripts/hooks/session-start` (Codex surface only, called with `--surface codex` from `.codex/hooks.json`), `scripts/term/sessions.sh`, `scripts/term/term.sh`, tests on the fake backend (must-pass and must-fail), the `orchestrate` skill section 9 and the README tool table.
- No change to `~/.codex` or any global setting.
