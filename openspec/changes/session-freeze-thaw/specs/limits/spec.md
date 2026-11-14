## MODIFIED Requirements

### Requirement: HOME-029 Acting on the verdict
The orchestrator SHALL work normally on `ok`, start nothing new on `soft`, and on `hard` freeze the tabs this home opened with `term.sh freeze <their ttys> --hard` and start nothing, re-running `freeze --continue <id>` for a tab kept while its turn ran once that turn ends, then reopen them after the reset time while its session runs.

#### Scenario: Hard stop
- **WHEN** `scripts/limits` prints `hard <reset>`
- **THEN** each idle tab this home opened is frozen with its resume line and open question in the freeze issue, and a tab in the middle of a turn is frozen once that turn ends

#### Scenario: Limit for one task
- **WHEN** a worker brief carries a `Limits: <mode>` line
- **THEN** that worker runs `scripts/limits` with `LIMITS_MODE=<mode>`
