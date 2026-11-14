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

### Requirement: HOME-082 The parent never works the child's issue
The sending orchestrator SHALL never claim, checkpoint, finish or label an issue in the target home, and SHALL only read it; a freeze run's own `Freeze <id>` issue in a related home is not a child's task issue, and the freeze and thaw it belongs to create, claim, checkpoint and finish it there.

#### Scenario: A child issue is open
- **WHEN** the child issue is still open
- **THEN** the parent writes nothing to it and waits for the sweep to report it closed

#### Scenario: A freeze in a related home
- **WHEN** a freeze includes a tab whose group's home is a related home
- **THEN** the freeze opens and claims a `Freeze <id>` issue in that home, and later checkpoints and finishes it

### Requirement: HOME-146 Handed-off work is not also done here
The orchestrator SHALL never also do, through its own subagents, a task it handed to a child home or a worker.

#### Scenario: An analysis goes to a child
- **WHEN** the orchestrator hands an analysis to a child home's session
- **THEN** it starts no subagent of its own for that analysis

### Requirement: HOME-157 A hand-off to another home is recorded here
When the orchestrator hands work to another home, it SHALL open and claim an issue in its own home first, also when the owner said to do nothing in this home, because the record and the `Parent:` link are not work.

#### Scenario: The owner says to do nothing here
- **WHEN** the owner asks to hand a task to another home and says to do nothing more in this one
- **THEN** this home holds a claimed issue for the hand-off and the target issue's body starts with `Parent:` naming it
