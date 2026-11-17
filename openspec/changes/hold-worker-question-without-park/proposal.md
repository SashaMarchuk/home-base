## Why
HELD: waits for the owner's yes. Do not apply or archive this change until the owner approves it.

HOME-080 says a session with the owner away parks its run with the question. HOME-148 says a worker with the owner away asks nothing, takes the reversible default and stores the question without parking, so it can keep going. The two approved requirements disagree for a worker; rule 5 already follows HOME-148.

## What Changes
- HOME-080 names the HOME-148 exception: a worker with the owner away stores the question with `home-log checkpoint <n> --question <text>` and keeps going on the reversible default; every other session parks.

## Impact
- `openspec/specs/questions/spec.md` only. No script changes: `home-log checkpoint --question` without `--park` exists already (HOME-017).
