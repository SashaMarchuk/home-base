## Why
A verified review of the freeze code tightened two rules whose requirement sentences no longer match: limits `hard` stays on `park` until the real-tab check of freeze and thaw passes, and the registry speaks for a tab only while its process and session file agree with it.

## What Changes
- HOME-029: on `hard`, the orchestrator parks every running task as before; freeze takes over only after the real-tab check.
- HOME-302: the registry's session id counts only while its pid is the live process and the session file names the same id; otherwise the tab is kept as changed.

## Impact
- `scripts/term/sessions.sh`, `scripts/term/freeze.sh`, the `orchestrate` skill, tests.
