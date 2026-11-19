## Why
The owner decided three working rules. A session that waits on the owner's own action (such as a browser sign-in) checks by itself before it asks again, and always asks through the ask tool so the owner notices. The orchestrator writes to a session only with a reason: the owner closed something, or gave context elsewhere that settles or changes that session's question or work, and then it passes on only that new context. When many changes go to one repository, the home may give their release to one separate session; a task that carries its own pull request keeps it until fully green.

## What Changes
- New HOME-445: waiting on an action only the owner can do, a session re-runs the check that proves it done after 1, 5 and 15 minutes by itself, goes on when it passes, and after the 15-minute check fails asks through the ask tool whether it is done (owner away: park with the question). The worker brief carries the rule.
- New HOME-446: the orchestrator writes to a session only with a reason and sends only the new context with its source; never a generic nudge, never its own instruction. "look at issue #n" (HOME-018), a dialog relay of the owner's exact words (HOME-107, HOME-126) and the message of `term.sh resume` (HOME-122) stay. A question on another home's issue that the owner answers in this home is passed to that home's live orchestrator session, or to a new one opened with the answer in its brief, never written on that issue.
- HOME-126 is narrowed to dialogs; outside a dialog HOME-446 applies.
- New HOME-447: a home may give the release of several changes to one repository to one separate session with its own issue, by its own judgment.
- New HOME-448: a task that carries its own pull request keeps it until every code-review comment is answered or fixed and every CI/CD check passed, then finishes with its link; no separate release session unless the owner says so. Rule 6 still applies.

## Impact
- The `orchestrate` skill (sections 3 and 4, the worker brief). No script changes.
