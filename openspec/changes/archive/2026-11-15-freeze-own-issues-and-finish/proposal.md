## Why
A review of the built freeze found two gaps against the approved safety rules: the park checkpoint on a tab's own issue could carry another home's question into this home, and could write to a number that is a child home's issue (an orchestrator tab); and a freeze issue whose caller stayed open was never finished by thaw.

## What Changes
- The own-issue park skips orchestrator tabs (their issue belongs to the child home) and carries the question only for a tab whose group belongs to this home.
- Thaw counts a session that is live already as back when it decides to finish a freeze issue.

## Impact
- `scripts/term/freeze.sh`, `scripts/term/thaw.sh`, tests.
