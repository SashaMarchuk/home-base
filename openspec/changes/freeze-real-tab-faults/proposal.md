## Why
The first real-tab check of freeze found two faults.

1. A fresh session's empty input box shows a placeholder hint. Freeze read it as text, probed it, saw the probe character come back alone (so it is no draft), read the screen again, found the hint back in the box and, after two probes, kept the tab as `kept:draft`. `send` and `close` go on straight after one good probe; freeze did not.
2. After `/clear` the session's process, tty and tab stay the same but its session file names a new session id. The registry still named the old one, so freeze kept the tab as `kept:changed`, and `park` would have written a resume line for the conversation that was cleared.

## What Changes
- HOME-311 and HOME-314: a box whose text one ghost probe shows to be a suggestion or a placeholder hint counts as empty; freeze types its `/exit` or its soft prompt straight after that probe and does not read the hint a second time. A real draft still keeps the tab.
- HOME-302: when a tab this home opened still has the recorded process on the recorded tty and tab id, and that process's session file names another session id, the tab keeps its registration and issue, and its id and resume line come from the session file. Freeze and park update the registry entry to the new id before any key, keeping the first id as the id of the run on the issue. A tab whose recorded process is gone or replaced is still `kept:changed`.
- New HOME-413: right before `/exit`, freeze reads the session file once more and keeps the tab as `kept:changed` when it no longer names the id that was recorded.
- Every fail-safe stays: no key without two agreeing signals, a real draft is never cleared, a running turn is never interrupted, nothing is signalled.

## Impact
- `scripts/term/freeze.sh`, `scripts/term/sessions.sh`, `scripts/term/term.sh` (`park`, `resume`), the fake backend (a placeholder that comes back), tests on the fake backend.
- The line in the `orchestrate` skill that keeps freeze and thaw off the owner's tabs until their real-tab check has passed is unchanged.
