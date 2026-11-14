# queue-and-labels Specification

## Purpose
A home's queue is its open GitHub issues, and its state is a fixed set of labels. Issues enter as inbox or ready, carry at most one status label, and the orchestrator dispatches ready issues to one worker each.

## Requirements

### Requirement: HOME-010 Fixed label set
`scripts/labels` SHALL create or update, safely when run twice, the labels `status:inbox`, `status:ready`, `status:claimed`, `status:parked`, `status:blocked`, `status:delegated`, `status:review`, the owner label named by `labels.needs_owner` (default `needs-owner`), `needs-summary`, `base-sync` and `dreams`.

#### Scenario: Run twice
- **WHEN** `scripts/labels` runs on a repo where the labels already exist
- **THEN** it updates their colours and descriptions and reports `labels: ok`

#### Scenario: No repo
- **WHEN** neither `home.config` nor `--repo` names a repo
- **THEN** it exits 2

### Requirement: HOME-078 Label failures in one line
`scripts/labels` SHALL check the repo before creating labels and stop at the first failure with one line and a non-zero exit: exit 3 on HTTP 404 (the repo cannot be reached), exit 4 on HTTP 403 (this login cannot manage labels) and exit 1 with the first line of the error otherwise.

#### Scenario: Repo not created yet
- **WHEN** the repo returns HTTP 404
- **THEN** it prints "cannot reach <repo>: create it on GitHub (private) and push, then run scripts/labels" and exits 3

#### Scenario: No permission
- **WHEN** the first label create returns HTTP 403
- **THEN** it prints "none created: this GitHub login cannot manage labels in <repo>. On a computer: `gh auth refresh -s repo`; in a web session: on github.com/settings/installations open Claude, Configure, and add this repository with read and write access. Then run scripts/labels.", creates no further label and exits 4

### Requirement: HOME-011 New issues enter as inbox or ready
`home-log new` SHALL return the number of an open issue with exactly the same title instead of creating one, and otherwise create an issue labelled `status:inbox`, or `status:ready` with `--ready`, or `status:<name>` with `--status <name>`, plus every `--label` given, and with the label `dreams` no status label at all.

#### Scenario: Unclear request
- **WHEN** `home-log new --title T --body B` runs without `--ready`
- **THEN** the new issue carries `status:inbox` and its number is printed

#### Scenario: Status given
- **WHEN** `home-log new` runs with `--status review`
- **THEN** the new issue carries `status:review` and no other `status:` label

#### Scenario: Standing Dreams issue
- **WHEN** `home-log new` runs with `--label dreams`, with or without `--ready` or `--status`
- **THEN** the issue carries `dreams` and no `status:` label

#### Scenario: Asked twice for the same issue
- **WHEN** `home-log new` runs with the title of an issue that is still open
- **THEN** no issue is created and the existing issue's number is printed

### Requirement: HOME-012 One status label at a time
Every status change made by `scripts/home-log` SHALL remove any other `status:` label from the issue before adding the new one.

#### Scenario: Claim of a ready issue
- **WHEN** a run claims an issue labelled `status:ready`
- **THEN** the issue carries `status:claimed` and no longer carries `status:ready`

### Requirement: HOME-013 Dispatch from the queue
The orchestrator SHALL pick `status:ready` issues oldest first with one worker per issue, after checking open claims and live tabs so that no task gets two sessions.

#### Scenario: Issue already running
- **WHEN** a ready issue already has a live session for it
- **THEN** no second worker is launched for it

#### Scenario: Worker brief
- **WHEN** a worker is launched for an issue
- **THEN** its brief, in the configured file language, names the home repo, the issue, the record tool and the start, finish and question commands, and quotes the owner's words verbatim

### Requirement: HOME-014 Turning a request into a task
The `task` skill SHALL search open issues, `DECISIONS.md` and the wiki before creating anything, and write the body with an outcome, a scope, checkable done-criteria, the owner's verbatim words and links only.

#### Scenario: Task already exists
- **WHEN** a matching open issue is found
- **THEN** the skill says so and creates nothing

#### Scenario: Inbox issue clarified
- **WHEN** an inbox issue has been clarified
- **THEN** its body is replaced and it moves from `status:inbox` to `status:ready`

### Requirement: HOME-015 Read-only status
The `status` skill SHALL read only, covering this home and every child home, and report open issues grouped as needs you, only you can do, running, frozen (issues titled `Freeze <id>`, with how many sessions each holds and how many hold an open question of the owner), parked, can close, and the counts of ready and inbox, skipping issues labelled `dreams`, and list an open pull request labelled `dreams` under needs you.

#### Scenario: Owner asks for status
- **WHEN** the owner asks "status"
- **THEN** the answer is short plain text with empty groups left out, ending with the one thing the owner should do first

#### Scenario: An open Dreams pull request
- **WHEN** a pull request labelled `dreams` is open
- **THEN** it is listed under needs you, while the standing `dreams` issue stays skipped

#### Scenario: A freeze is open
- **WHEN** a `Freeze <id>` issue is open with five sessions, two of them holding a question
- **THEN** status lists it under Frozen with those two counts and not again under Parked

### Requirement: HOME-128 The orchestrator reads its skill and honours a requested session
A session in a home SHALL read the orchestrate skill before acting on a request, open a separate session when the owner asks for one, and never close a session that still holds an open question of the owner without the owner's word.

#### Scenario: The owner asks for another terminal
- **WHEN** the owner says a task should run in its own session
- **THEN** the orchestrator opens that session with a brief and does not do the task itself

#### Scenario: Closing finished sessions
- **WHEN** the orchestrator closes finished sessions and one of them holds an open question of the owner
- **THEN** that session is parked or left open, not closed

### Requirement: HOME-167 A session never raises its own tab cap
A session SHALL never change `term.max_workers` itself; at the cap it queues the rest with a stated reason, and a child orchestrator's brief says how many tabs it may open, never to launch all.

#### Scenario: More tasks than the cap
- **WHEN** seven tasks are ready and the cap allows four tabs
- **THEN** the session opens four, queues three with the reason stated and leaves `term.max_workers` unchanged

### Requirement: HOME-171 A worker brief names the owner's language
Every worker brief SHALL state that questions and every message to the owner, the final status included, are in the owner's language.

#### Scenario: A worker runs in a code checkout
- **WHEN** a worker starts in a folder with no home configuration
- **THEN** its brief still names the owner's language for its questions and its final status

### Requirement: HOME-173 Steps that do not wait go on
When one step of the owner's ask waits on the owner, the session SHALL carry on with the later steps that do not depend on it.

#### Scenario: A purchase waits on the owner
- **WHEN** one step waits on the owner's click and a later step does not need it
- **THEN** the session does the later step while the first one waits
