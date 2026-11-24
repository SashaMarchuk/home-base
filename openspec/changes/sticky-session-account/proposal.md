## Why
A Claude Code session that was first launched under one account (profile) was later resumed under another. The owner ruled that this must not happen: a session keeps the account it was first launched on, and every home records that account and resumes on it.

Today nothing holds that account. `term.sh` records the profile of the process it sees (HOME-129, HOME-412), so a session resumed under another profile and then adopted is recorded under the new one, and every later resume repeats the mistake. Hand-written reopen scripts outside the home had the same fault: their profile maps disagreed with the sessions' own transcripts.

Fact used (read only, on the owner's laptop): each start or resume of a session writes, into its transcript, the path of the user instruction file it loaded. That path sits in the profile's own folder, so the first such path names the profile the session was first launched under.

## What Changes
- Base hard rule 13 gains one sentence: a session is resumed only under the profile it was first launched under.
- New HOME-484: once a profile is recorded for a session id, `term.sh` never replaces it. `adopt`, `park`, `freeze`, `reopen` and `resume` keep the first recorded profile in the resume line; a live session that runs under another profile is reported, not re-recorded.

## Impact
- `CLAUDE.md` base block (rule 13), now.
- `scripts/term/term.sh`, `scripts/term/recover.sh`, `scripts/term/sessions.sh` and their fake-backend tests, later (tasks 1.2-1.3).
- Open: whether `term.sh` should also read the first profile from the transcript for a session it never recorded. Not part of this change.
