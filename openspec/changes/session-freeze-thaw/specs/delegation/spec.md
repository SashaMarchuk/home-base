## MODIFIED Requirements

### Requirement: HOME-082 The parent never works the child's issue
The sending orchestrator SHALL never claim, checkpoint, finish or label an issue in the target home, and SHALL only read it; a freeze run's own `Freeze <id>` issue in a related home is not a child's task issue, and the freeze and thaw it belongs to create, claim, checkpoint and finish it there.

#### Scenario: A child issue is open
- **WHEN** the child issue is still open
- **THEN** the parent writes nothing to it and waits for the sweep to report it closed

#### Scenario: A freeze in a related home
- **WHEN** a freeze includes a tab whose group's home is a related home
- **THEN** the freeze opens and claims a `Freeze <id>` issue in that home, and later checkpoints and finishes it
