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
The `status` skill SHALL read only, covering this home and every child home, and report open issues grouped as needs you, only you can do, running, parked, can close, and the counts of ready and inbox, skipping issues labelled `dreams`.

#### Scenario: Owner asks for status
- **WHEN** the owner asks "status"
- **THEN** the answer is short plain text with empty groups left out, ending with the one thing the owner should do first
