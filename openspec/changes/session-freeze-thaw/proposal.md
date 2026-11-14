## Why
The owner asked for session management: freeze every session with a snapshot and restore it later; close one session, a selection, a group or a window; open sessions in fixed windows per group; a soft close that asks a session to pause itself; and a hard close that keeps the active state and open questions. Closing by hand failed before because a tab's identity (session id, profile) could not be read from its command line, and nothing excluded the calling session.

## What Changes
- Session identity from the per-session files Claude Code writes, `survey --json`, the calling session found by two signals, resume lines that keep the profile.
- Groups and windows: group keys in `.local/config` only, `open --group`, the window of a group resolved on each open.
- `freeze` (soft, hard, soft-then-hard) with the snapshot and the record written before the first key, one `Freeze <id>` issue per owning home, and the conservative defaults: a real draft keeps its tab, a running turn is never interrupted.
- `thaw`.
- `configure --set` learns the `term.*` keys.
- The orchestrator closes or freezes only sessions the owner named and asks before a bulk close; the no-confirmation rule for a named scope applies only after the real-tab check passes. Limits `hard` freezes this home's own tabs. `status` lists frozen sessions.
- Not in this change (held for the owner's approval in `hold-freeze-opt-ins`): saving and clearing a draft, interrupting a running turn, and writing into another home's `.local/`.

## Impact
- `scripts/term/term.sh`, `scripts/term/sessions.sh`, `scripts/term/freeze.sh`, `scripts/term/thaw.sh`, `scripts/configure`, the fake backend and tests.
- `orchestrate` and `status` skills.
