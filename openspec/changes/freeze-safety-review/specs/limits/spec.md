## MODIFIED Requirements

### Requirement: HOME-029 Acting on the verdict
The orchestrator SHALL work normally on `ok`, start nothing new on `soft`, and on `hard` park every running task as soon as its turn has ended and start nothing, then resume parked tasks after the reset time while its session runs; it uses `freeze` for this only after the real-tab check of freeze and thaw has passed.

#### Scenario: Hard stop
- **WHEN** `scripts/limits` prints `hard <reset>`
- **THEN** each idle worker tab is parked with its resume command and open question written to its issue, and a tab in the middle of a turn is parked once that turn ends

#### Scenario: Limit for one task
- **WHEN** a worker brief carries a `Limits: <mode>` line
- **THEN** that worker runs `scripts/limits` with `LIMITS_MODE=<mode>`
