# delegation Specification

## Purpose
A home hands work to a parent, child or peer home through an issue in that home. The receiving home owns its queue; the sending home only reads the result and closes its own issue when the child closes.

## Requirements

### Requirement: HOME-022 Handoff through an issue in the target home
Delegation SHALL start from an issue claimed in the sending home and create a `status:ready` issue in the target home's repo with `home-log new --repo <target> --ready`, whose body starts with `Parent: <this repo>#<n>` followed by the brief and the owner's verbatim words.

#### Scenario: Peer handoff
- **WHEN** work is handed to a peer home
- **THEN** the new issue carries a brief and links only, no content of the sending home's domain

#### Scenario: The owner asks for the target home's work directly
- **WHEN** the owner asks the sending orchestrator for work that belongs to another home and no issue exists yet
- **THEN** the sender opens and claims an issue in its own home before it creates the child issue

### Requirement: HOME-023 The parent issue records the child
`home-log checkpoint <n> --delegated <repo>#<m>` SHALL set the parent issue to `status:delegated` and write `- delegated: <repo>#<m>` into the run's comment.

#### Scenario: Delegated checkpoint
- **WHEN** the orchestrator delegates issue 5 to a child issue
- **THEN** issue 5 carries `status:delegated` and its comment links the child issue

### Requirement: HOME-024 Starting the target orchestrator
With terminal helpers on, the sending orchestrator SHALL open an orchestrator tab in the target home, recording the child issue with it, only when no live session runs there, and otherwise send that session the text "look at issue #m" and nothing else.

#### Scenario: Target already running
- **WHEN** a live session already runs in the target home's folder
- **THEN** no new tab is opened and that session receives only "look at issue #m"

#### Scenario: Helpers off
- **WHEN** terminal helpers are off
- **THEN** nothing is opened and the child issue waits as `status:ready`

### Requirement: HOME-025 The child owns its queue
The sending home SHALL never write labels or comments on the child issue and only read it.

#### Scenario: Child in progress
- **WHEN** the child issue is claimed in the target home
- **THEN** the parent home changes nothing on it

### Requirement: HOME-026 Closing the parent when the child closes
The sweep, when run without `--same-repo`, SHALL report `SWEEP delegated-child-closed` for each `status:delegated` issue whose recorded child issue is closed.

#### Scenario: Child finished
- **WHEN** the child issue is closed
- **THEN** the sweep reports it and the orchestrator finishes the parent with "Done in <child link>: <one line>"
