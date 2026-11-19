## MODIFIED Requirements

### Requirement: HOME-022 Handoff through an issue in the target home
A hand-off SHALL create one `status:ready` issue in the target home's repo with `home-log new --repo <target> --ready`, whose body holds the brief and the owner's verbatim words, and SHALL open, claim or keep no issue for that work in the sending home, also when the request came straight from the owner there; context the target needs SHALL be given as a link, never copied.

#### Scenario: Peer handoff
- **WHEN** work is handed to a peer home
- **THEN** the new issue carries a brief and links only, no content of the sending home's domain

#### Scenario: The owner asks for the target home's work directly
- **WHEN** the owner asks the sending orchestrator for work that belongs to another home and no issue exists yet
- **THEN** the only issue for it is the one created in the target home, and the sending home's repo gains no issue

### Requirement: HOME-023 The parent issue records the child
`home-log checkpoint <n> --delegated <repo>#<m>` SHALL set an older parent issue, handed off under the earlier rule, to `status:delegated` and write `- delegated: <repo>#<m>` into the run's comment; no new hand-off SHALL use it.

#### Scenario: Delegated checkpoint
- **WHEN** an older parent issue 5 is checkpointed with `--delegated` and a child issue
- **THEN** issue 5 carries `status:delegated` and its comment links the child issue

#### Scenario: A new hand-off
- **WHEN** the orchestrator hands new work to another home
- **THEN** it runs no `checkpoint --delegated` and no issue in its own home carries `status:delegated` for that work

### Requirement: HOME-026 Closing the parent when the child closes
The sweep, when run without `--same-repo`, SHALL report `SWEEP delegated-child-closed` for each `status:delegated` issue whose recorded child issue is closed, so that older parent issues are still finished.

#### Scenario: Child finished
- **WHEN** the child issue of an older `status:delegated` issue is closed
- **THEN** the sweep reports it and the orchestrator finishes the parent with "Done in <child link>: <one line>"

#### Scenario: Child still open
- **WHEN** the child issue of an older `status:delegated` issue is open
- **THEN** the sweep reports nothing for it

### Requirement: HOME-082 The parent never works the child's issue
The sending orchestrator SHALL never claim, checkpoint, finish, label or comment on an issue in the target home, and SHALL only read it, leaving it to the target home to close; a freeze run's own `Freeze <id>` issue in a related home is not a child's task issue, and the freeze and thaw it belongs to create, claim, checkpoint and finish it there.

#### Scenario: A child issue is open
- **WHEN** the child issue is still open
- **THEN** the parent writes nothing to it and shows it in its status until the target home closes it

#### Scenario: A freeze in a related home
- **WHEN** a freeze includes a tab whose group's home is a related home
- **THEN** the freeze opens and claims a `Freeze <id>` issue in that home, and later checkpoints and finishes it

## REMOVED Requirements

### Requirement: HOME-157 A hand-off to another home is recorded here
**Reason**: A task lives in one issue, in the home that owns the work; the sending home keeps no issue and no copy (HOME-022).
**Migration**: Older parent issues stay valid and are finished through HOME-026; new hand-offs open only the target issue.
