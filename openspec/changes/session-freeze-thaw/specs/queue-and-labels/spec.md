## MODIFIED Requirements

### Requirement: HOME-015 Read-only status
The `status` skill SHALL read only, covering this home and every child home, and report open issues grouped as needs you, only you can do, running, frozen (issues titled `Freeze <id>`, with how many sessions each holds and how many hold an open question of the owner), parked, can close, and the counts of ready and inbox, skipping issues labelled `dreams`.

#### Scenario: Owner asks for status
- **WHEN** the owner asks "status"
- **THEN** the answer is short plain text with empty groups left out, ending with the one thing the owner should do first

#### Scenario: A freeze is open
- **WHEN** a `Freeze <id>` issue is open with five sessions, two of them holding a question
- **THEN** status lists it under Frozen with those two counts and not again under Parked
