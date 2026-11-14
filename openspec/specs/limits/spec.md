# limits Specification

## Purpose
A home can stop starting work, or park running work, when usage of the model subscription nears a threshold. The usage reader is a per-machine hook point, and a missing or broken reader never blocks work.

## Requirements

### Requirement: HOME-027 Limits verdict
`scripts/limits` SHALL print `ok`, `soft` or `hard` followed by the next reset time or `-`, taking the mode from `.local/limits` while its optional `until` time has not passed, else from `LIMITS_MODE`, else from `limits.mode` (default `none`).

#### Scenario: Mode none
- **WHEN** the resolved mode is `none`
- **THEN** it prints `ok -`

#### Scenario: Owner's live word expired
- **WHEN** `.local/limits` holds `mode=hard` with an `until` time in the past
- **THEN** that line is ignored and the next source decides the mode

#### Scenario: Unknown mode
- **WHEN** the resolved mode is not `none`, `soft` or `hard`
- **THEN** a warning is printed and the mode `none` is used

### Requirement: HOME-028 Threshold from the usage reader
When a mode is set, `scripts/limits` SHALL run the executable named by `limits.reader`, which prints the five-hour percentage, the weekly percentage and the next reset time, and print the mode when either percentage reaches `limits.threshold` (default 90), else `ok`.

#### Scenario: Weekly use over the threshold
- **WHEN** the mode is `soft` and the reader prints a weekly percentage of 93 with the threshold 90
- **THEN** it prints `soft <reset>`

#### Scenario: No reader
- **WHEN** `limits.reader` is unset, not executable, fails or prints nothing
- **THEN** it prints `ok -` and one warning line

### Requirement: HOME-029 Acting on the verdict
The orchestrator SHALL work normally on `ok`, start nothing new on `soft`, and on `hard` freeze the tabs this home opened with `term.sh freeze <their ttys> --hard` and start nothing, re-running `freeze --continue <id>` for a tab kept while its turn ran once that turn ends, then reopen them after the reset time while its session runs.

#### Scenario: Hard stop
- **WHEN** `scripts/limits` prints `hard <reset>`
- **THEN** each idle tab this home opened is frozen with its resume line and open question in the freeze issue, and a tab in the middle of a turn is frozen once that turn ends

#### Scenario: Limit for one task
- **WHEN** a worker brief carries a `Limits: <mode>` line
- **THEN** that worker runs `scripts/limits` with `LIMITS_MODE=<mode>`

### Requirement: HOME-131 Keeping the machine awake
An orchestrator that keeps the machine awake SHALL run only `caffeinate -w <pid of this session>`, never a timed or orphan caffeinate.

#### Scenario: A long unattended run
- **WHEN** the orchestrator must keep the machine awake while its session runs
- **THEN** it starts `caffeinate -w` with its own session's PID, and the assertion ends with that session

### Requirement: HOME-133 A stated cap counts every tab
A cap on sessions that the owner states SHALL count every tab the orchestrator opens, child orchestrators included.

#### Scenario: A cap of three to four sessions
- **WHEN** the owner says "3-4 sessions" and the orchestrator has opened two child orchestrators
- **THEN** at most two more tabs are opened across all homes
