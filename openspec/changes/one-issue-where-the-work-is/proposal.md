## Why
A hand-off to another home today makes two issues: a claimed parent issue in the sending home and the working issue in the target home, linked by a `Parent:` line, with the sweep finishing the parent when the child closes. The owner decided that a task lives in one issue only, in the home that owns the work, whichever home it was started from; the sending home keeps no issue and no copy. Tasks started directly in a child home and tasks handed to it then look the same, and the parent sees both through its combined status (change combined-status).

## What Changes
- HOME-022: a hand-off opens one `status:ready` issue in the target home with `home-log new --repo <target> --ready`, holding the brief and the owner's verbatim words; nothing is opened or claimed in the sending home, also when the request came straight from the owner there. Context goes in as a link, never as a copy. No `Parent:` line.
- HOME-023 and HOME-026: `checkpoint --delegated`, the `status:delegated` label and the sweep's `delegated-child-closed` stay for older issues handed off under the earlier rule; no new hand-off uses them.
- HOME-157 is removed: a hand-off no longer opens or claims an issue in the sending home.
- HOME-082: the sending home also writes no comment on the target issue and shows it in its status until the target home closes it, instead of waiting for the sweep.
- HOME-124: the session-start line adds that another home's work gets its one issue there and none here.
- HOME-025 and HOME-146 stand: only the owning home works and closes its issue.

## Impact
- `CLAUDE.md` rule 1, the `orchestrate` skill (header, sections 2 and 7), the `task` skill (step 3), the session-start reminder line (HOME-124), the header comments of `scripts/home-log` and `scripts/home-sweep`.
- No script behaviour changes; a sweep test now covers an older hand-off whose issue closed.
