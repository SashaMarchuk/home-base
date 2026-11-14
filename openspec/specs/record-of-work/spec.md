# record-of-work Specification

## Purpose
Every task of a home is a GitHub issue, and `scripts/home-log` is the only writer of task state on it: one comment per session run, a claim, checkpoints and one final comment. The sweep reports gaps in that record and never repairs them.

## Requirements

### Requirement: HOME-001 One marked comment per run
`scripts/home-log` SHALL keep exactly one comment per run on an issue, starting with the hidden marker `<!-- home-log run=<id> state=<state> -->` and holding the run id, the runner (host, surface, working directory), the resume command and the UTC update time, and it treats a comment without that marker as written by a person.

#### Scenario: Later writes update the same comment
- **WHEN** a run that already has a comment on an issue writes a checkpoint
- **THEN** that comment is edited in place and no second comment of the run is posted

#### Scenario: A person's comment is not a run
- **WHEN** an issue holds a comment without the marker
- **THEN** no verb of `scripts/home-log` reads it as a claim, checkpoint or final comment

### Requirement: HOME-002 Run identity
`scripts/home-log` SHALL take the run id from `--run-id`; without it, `start` takes the Claude Code session id, else the Codex thread id, else the run stored in `.local/runs/` for the issue, else a new random id, while every other verb takes the stored run before the session or thread id; any run id holding characters other than letters, digits, dot, underscore and hyphen is refused with exit 2.

#### Scenario: Session id is the run id
- **WHEN** `home-log start 12` runs inside a Claude Code session with no `--run-id`
- **THEN** the comment's run id is that session's id

#### Scenario: Later verbs use the stored run
- **WHEN** `.local/runs/12` records the run that won the claim and `home-log checkpoint 12` runs in a session with another session id
- **THEN** the checkpoint writes the stored run's comment

#### Scenario: Invalid run id
- **WHEN** `--run-id "a b"` is passed
- **THEN** the script exits 2 and writes nothing

### Requirement: HOME-003 Claim on start
`home-log start <n>` SHALL claim an open issue for one run only: it refuses with exit 3 while another run holds an active comment, posts or reactivates the run's comment as `active`, sets `status:claimed` unless the issue is labelled `dreams`, re-reads the comments after a settle delay, and records the run in `.local/runs/` only when its own active comment is the oldest, else deletes its comment and exits 3.

#### Scenario: Two runs race for one issue
- **WHEN** two runs start the same issue at nearly the same time
- **THEN** the run whose active comment is oldest keeps the claim and records the run locally, and the other exits 3 with its comment removed and no run recorded

#### Scenario: Closed issue
- **WHEN** `home-log start` targets a closed issue
- **THEN** it exits 2 and asks to reopen it or open a new issue

#### Scenario: Finished run starts again
- **WHEN** a run whose comment on the issue is `final` runs `start` again
- **THEN** it exits 5 and writes nothing

#### Scenario: Same run starts twice
- **WHEN** the run that already holds the active claim runs `start` again
- **THEN** it exits 0 and reports that this run already holds the claim

### Requirement: HOME-004 Checkpoints and pauses
`home-log checkpoint <n>` SHALL rewrite the run's comment only while it is `active`, `parked`, `blocked` or `delegated` (or, with `--handed`, post it when the run has none), exiting 5 when it is `final`, `released` or `stub`, keep its earlier text, question and delegation unless replaced, and with `--park`, `--blocked <reason>` or `--delegated <repo>#<m>` set the state and the matching `status:` label and remove the local run file.

#### Scenario: Park
- **WHEN** `home-log checkpoint 7 --park` runs
- **THEN** the comment state is `parked`, the issue carries `status:parked` and the local run file is removed

#### Scenario: Checkpoint without a claim
- **WHEN** a run with no comment on the issue writes a checkpoint without `--handed`
- **THEN** it exits 2 and says to run `home-log start` first

#### Scenario: Checkpoint after the run ended
- **WHEN** a run whose comment is `final`, `released` or `stub` writes a checkpoint
- **THEN** it exits 5, the comment is unchanged and it says to run `home-log start` to work on the issue again

### Requirement: HOME-005 Finish
`home-log finish <n>` SHALL refuse with exit 3 while another run holds an active comment on the issue, otherwise write the run's final comment without an open question, remove `needs-summary` and the owner label, then close the issue as completed with no status label, or with `--review` set `status:review` and leave it open, or with `--release <reason>` mark the comment `released` and return the issue to `status:ready`, or on the standing Dreams issue keep its status labels and leave it open.

#### Scenario: Plain finish
- **WHEN** `home-log finish 9 --text "Result: <link>"` runs
- **THEN** the comment state is `final`, every `status:` label is removed and the issue is closed as completed

#### Scenario: Another run holds the claim
- **WHEN** another run's comment on the issue is still `active`
- **THEN** the script exits 3, names that run and writes nothing

#### Scenario: Already finished by another run
- **WHEN** another run wrote a final comment newer than this run's own comment and neither `--release` nor the standing Dreams issue applies
- **THEN** the script exits 5 and writes nothing

#### Scenario: A reopened issue starts over
- **WHEN** a finished issue is reopened and a new run starts and then finishes it
- **THEN** the older final comment does not block the finish

#### Scenario: Open question cleared
- **WHEN** a run whose comment holds an open question finishes
- **THEN** the final comment holds no open question and the owner label is removed

#### Scenario: Standing Dreams issue
- **WHEN** a run finishes on the standing issue labelled `dreams`
- **THEN** `needs-summary` and the owner label are removed, no status label changes and the issue stays open

#### Scenario: Release a dead claim
- **WHEN** `home-log finish 4 --run-id <dead run> --release "tab gone"` runs
- **THEN** the dead run's comment becomes `released` and the issue returns to `status:ready`

### Requirement: HOME-006 No personal values in the record
`scripts/home-log` SHALL scan every title, body, text, question, blocked reason and release reason against the personal-value patterns and the boundary terms before writing, exiting 4 with nothing written on a hit.

#### Scenario: A phone number in a summary
- **WHEN** a finish text contains a phone number
- **THEN** the script exits 4, prints the masked hit and the issue is unchanged

### Requirement: HOME-007 Stub at session end
The session-end hook SHALL, for each claim of the ending session whose comment is still `active`, rewrite that comment as a `stub` with the session's resume command, add the `needs-summary` label, and never block the session from ending.

#### Scenario: Session closes without a final comment
- **WHEN** a session that claimed issue 3 ends before `home-log finish`
- **THEN** issue 3 shows a `stub` comment with the resume command and carries `needs-summary`

#### Scenario: Codex session
- **WHEN** the ending session's surface is codex (`CODEX_THREAD_ID` is set)
- **THEN** the stub's resume command is `codex resume <id>`

#### Scenario: Session without a claim
- **WHEN** a session that holds no claim ends
- **THEN** nothing is written

### Requirement: HOME-008 The sweep reports and never repairs
`scripts/home-sweep` SHALL print one `SWEEP <kind> <repo>#<n> <detail>` line per finding of the kinds `closed-no-final`, `stale-claim`, `pr-no-final` and `delegated-child-closed`, add `needs-summary` to `closed-no-final` and `pr-no-final` issues, change nothing else, skip the delegated and base checks with `--same-repo`, and exit 0 when there is no `home.config` or on any network error.

#### Scenario: Stale claim
- **WHEN** a `status:claimed` issue's active comment is older than `sweep.stale_hours` (default 6)
- **THEN** the sweep prints `SWEEP stale-claim` for it and leaves the claim untouched

#### Scenario: Closed without a final comment
- **WHEN** a closed issue updated within `sweep.lookback_days` (default 14) has no final comment and is not labelled `dreams`
- **THEN** the sweep prints `SWEEP closed-no-final` and labels it `needs-summary`

#### Scenario: Daily run in CI
- **WHEN** the scheduled `home-sweep` workflow runs in a home
- **THEN** it runs the sweep with `--same-repo` and writes the findings to the job summary

#### Scenario: The workflow file changes
- **WHEN** a push changes the `home-sweep` workflow file
- **THEN** the workflow runs once on that push, as it does on its schedule

### Requirement: HOME-009 Repair by the orchestrator
The orchestrator SHALL close each gap the sweep reports with `home-log finish`, using a pull request link when one holds the result, else a summary of at most ten lines from the local transcript, else the text "No transcript or PR found; nothing recorded.", and treat a claim as dead only when both its tab and its process are gone.

#### Scenario: Silence alone
- **WHEN** a claim is reported stale but its process still runs
- **THEN** the claim is left in place and the status says so

#### Scenario: Dead claim
- **WHEN** a stale claim's tab and recorded process are both gone
- **THEN** the orchestrator resumes it or releases it with the dead run's id

### Requirement: HOME-123 The record follows reality
A session SHALL write a result to the record only after it verified that result by reading back its effect, and SHALL never report a count it did not observe.

#### Scenario: A loop of writes
- **WHEN** a session posts entries in a loop and some of them fail
- **THEN** the record reports only the entries whose responses confirm them

### Requirement: HOME-130 A stub keeps the run's text and question
`home-log stub` SHALL keep the run's previous text and open question and add the line "Session ended without a final summary." after that text.

#### Scenario: A session ends after a checkpoint
- **WHEN** a run checkpointed issue 5 with a text and a question and its session ends without `home-log finish`
- **THEN** the stub comment on issue 5 still holds that text and that question, followed by the stub line

### Requirement: HOME-140 A worker's issue is claimed by the worker
When the orchestrator hands a request's issue to a worker, it SHALL open the issue with `--ready` and leave its claim to that worker's own `home-log start`, claiming only issues it works itself.

#### Scenario: A task goes to a worker tab
- **WHEN** the orchestrator opens issue 5 and launches a worker for it
- **THEN** the orchestrator has not claimed issue 5 and the worker's `home-log start 5` succeeds

### Requirement: HOME-155 Open and claim in one call
`home-log new --start` SHALL open the issue (or take the open issue with exactly the same title), print only its number on stdout, and then claim it for the run with the same logic and exit codes as `home-log start`, refusing with exit 2 when combined with `--ready`, `--status` or the label `dreams`, while `home-log new` without `--start` writes no comment and claims nothing.

#### Scenario: One call opens and claims
- **WHEN** `home-log new --title T --body B --start` runs and no open issue has that title
- **THEN** stdout holds only the new number, the issue carries `status:claimed` and the run's one `active` comment, and the run is recorded in `.local/runs/`

#### Scenario: The same title is held by another run
- **WHEN** `home-log new --start` runs with the title of an open issue on which another run holds an active comment
- **THEN** stdout holds that issue's number, no comment is added and the script exits 3

#### Scenario: A forgotten finish
- **WHEN** a session that ran `home-log new --start` ends without `finish`
- **THEN** the session-end hook turns its comment into a stub and adds `needs-summary`

#### Scenario: Plain new
- **WHEN** `home-log new --title T --body B` runs without `--start`
- **THEN** the issue is `status:inbox` with no comment and no run recorded

### Requirement: HOME-156 A hand-off to a worker is recorded without a claim
`home-log checkpoint <n> --handed <session id>` SHALL write the run's comment as `delegated` with the session id in its own `- handed:` line, posting it when the run has no comment yet, change no label, record no run in `.local/runs/`, refuse with exit 2 an id holding characters other than letters, digits, dot, underscore and hyphen or a combination with `--park`, `--blocked` or `--delegated`, and keep the id out of the sensitive-text check.

#### Scenario: The orchestrator hands an issue to a worker
- **WHEN** the orchestrator runs `home-log new --ready`, opens a worker tab and runs `home-log checkpoint 5 --handed <session id>` without having claimed issue 5
- **THEN** issue 5 holds one `delegated` comment of the orchestrator's run with the `- handed:` line, keeps `status:ready`, and the worker's `home-log start 5` exits 0

#### Scenario: Invalid session id
- **WHEN** `--handed "a b"` is passed
- **THEN** the script exits 2 and writes nothing

### Requirement: HOME-168 A resumed session's question is kept
When a resumed session had stopped at a question, the finish text SHALL quote that question with its session, and while its menu is not seen again the issue finishes with `--review` instead of closing.

#### Scenario: Four resumed sessions held questions
- **WHEN** the orchestrator resumes four sessions that stopped at questions and their menus are not seen again
- **THEN** the finish text quotes the four questions with their sessions and the issue is left for review, not closed

### Requirement: HOME-172 An issue closes only when its task is met
An issue SHALL be closed only when every item of its task, its "Done when" or the brief's task list, is met; otherwise it finishes with `--review`, naming the unmet item.

#### Scenario: One item is unverified
- **WHEN** a worker finishes with one item of its brief's task list unverified
- **THEN** it runs `finish --review` naming that item and does not close the issue
