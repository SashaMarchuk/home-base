## MODIFIED Requirements

### Requirement: HOME-307 One freeze issue per owning home
After the snapshot, `term.sh freeze` SHALL open and claim one `Freeze <id>` issue in each owning home (`term.group.<g>.home`: `self` or a name of `homes.*`) with `home-log`, read it back, park the own issue of a worker or owner tab bound to one (with its question only when its group belongs to this home), and type nothing into a tab whose record failed.

#### Scenario: The record fails
- **WHEN** creating the freeze issue fails
- **THEN** no tab receives a key and each tab of that home is listed as `kept:no-record`

#### Scenario: An orchestrator tab with a child's issue
- **WHEN** an orchestrator tab opened for a child home's issue is frozen
- **THEN** no issue of this home with that number is written

### Requirement: HOME-317 Thaw reopens by group
`term.sh thaw [<id>|latest]` SHALL reopen a freeze's closed sessions and its caller in their group windows, in `term.groups` order, with their recorded resume lines and one message (re-ask an open question; read the soft checkpoint first; else continue), type nothing after the launch line, and finish each freeze issue once each of its sessions is reopened or live already.

#### Scenario: Open question
- **WHEN** a frozen session had a dialog open
- **THEN** its reopened tab is asked to re-ask its open question

#### Scenario: The caller stayed open
- **WHEN** the only session of a freeze issue not reopened is the caller, still live
- **THEN** thaw finishes that freeze issue
