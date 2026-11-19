## MODIFIED Requirements

### Requirement: HOME-320 Closing sessions the owner named
The `orchestrate` skill SHALL close or freeze only sessions the owner named, ask once before closing or freezing several at once and never offer to freeze every session, except for finished tabs under HOME-416; only once the real-tab check of freeze and thaw has passed SHALL a freeze, thaw or close whose scope the owner named run without a confirmation.

#### Scenario: Before the real-tab check
- **WHEN** the owner says to close the sessions of one group and the real-tab check has not passed
- **THEN** the orchestrator asks once before freezing them

### Requirement: HOME-061 Close only a finished session
`term.sh close` SHALL close only a tab this home opened, for an issue given with `--issue` or recorded at open (exit 2 without one), whose issue on GitHub has a final `home-log` comment of that session's own run (the id the session started with; for the owner's own tab under HOME-106 a final comment of any run) and no owner label, and whose screen shows no dialog, no running turn, no background job and an empty input box, refusing with exit 3 otherwise or when the issue cannot be read, and then verify that the session's process is gone.

#### Scenario: No final comment
- **WHEN** the tab's issue has no final `home-log` comment
- **THEN** close exits 3 and the tab stays open

#### Scenario: Only another run finished the issue
- **WHEN** the tab's issue has a final `home-log` comment of an earlier run and none of the run of the session in that tab
- **THEN** close exits 3, types nothing and the tab stays open

#### Scenario: Question waiting on the owner
- **WHEN** the tab's issue carries the owner label
- **THEN** close exits 3 and the tab stays open

#### Scenario: Issue cannot be read
- **WHEN** the issue's comments or labels cannot be read from GitHub
- **THEN** close exits 3 and the tab stays open

## ADDED Requirements

### Requirement: HOME-414 Which tabs are finished
`term.sh finished` SHALL print `<tty> <session id> <issue|-> <verdict>` for every open tab of this home's registry (`--json`: one object per tab, with the repo of its issue), the verdict being `closable`, `keep:<reason>` or `unsure:<what could not be read>` from the checks of `close` (HOME-061) in their order, and SHALL send no key, write no file and close nothing.

#### Scenario: A finished worker
- **WHEN** a worker tab's issue has a final `home-log` comment of that worker's run and no owner label, and its screen shows an empty box and nothing running
- **THEN** `finished` prints `closable` for it

#### Scenario: Nothing is touched
- **WHEN** `finished` runs over tabs with a notice, a dialog, a draft and an empty box
- **THEN** no tab receives a key and the registry is unchanged

### Requirement: HOME-415 Closable tabs
`term.sh finished` SHALL say `closable` only when the issue has a final `home-log` comment of the run of the session in that tab (the id the session started with) and no owner label, and the session's process is gone or its screen shows no dialog, running turn or background job and an empty input box.

#### Scenario: The session ended on its own
- **WHEN** the issue is final and the session's process is gone while its tab is still open
- **THEN** the verdict is `closable`

#### Scenario: This run's final beside another run's
- **WHEN** the issue holds a final `home-log` comment of an earlier run and one of the run of the idle session in that tab
- **THEN** the verdict is `closable`

### Requirement: HOME-419 Kept tabs
`term.sh finished` SHALL say `keep:<reason>` for a tab that is gone, the calling session, no issue, no final comment, a final comment of another run only, an owner label, a dialog, a running turn, background work, a Codex tab without its thread id, or a session that moved to another id.

#### Scenario: An open question
- **WHEN** the tab's issue carries the owner label
- **THEN** the verdict is `keep:owner-question`

#### Scenario: The owner reused the tab
- **WHEN** the session's own file names another id than the registry entry (as after `/clear` or `/resume`), or the entry records such a move, and the issue has a final comment of the first id's run
- **THEN** the verdict is `keep:moved`, and only the owner's word closes that tab

#### Scenario: A follow-up worker on a finished issue
- **WHEN** a second worker's tab is open on an issue whose only final `home-log` comment is of the first worker's run, and that tab is idle with an empty box
- **THEN** the verdict is `keep:other-run`

### Requirement: HOME-420 A recorded adopted tab stays the owner's own
`term.sh finished` SHALL say `keep:owner-tab` for a tab recorded with `adopted: true` (the owner's own tab; every Codex tab is one), and `term.sh close` SHALL refuse such a tab with exit 3, typing nothing, unless `--adopt` is given again.

#### Scenario: An adopted tab with a finished issue
- **WHEN** a tab recorded with `adopted: true` is idle with an empty box and its issue has a final `home-log` comment and no owner label
- **THEN** `finished` prints `keep:owner-tab` for it

#### Scenario: Close without the flag
- **WHEN** `term.sh close <tty>` runs on that tab without `--adopt`
- **THEN** it exits 3 and nothing is typed

#### Scenario: Close with the flag
- **WHEN** the owner named that tab and `term.sh close <tty> --adopt` runs on it
- **THEN** the checks of close run as before and the session exits

### Requirement: HOME-418 What finished cannot decide
`term.sh finished` SHALL say `unsure:<what>` when another program runs under the recorded process id, the issue or its repo cannot be read, the screen cannot be read or shows no input box, a notice is shown, or the box holds text, and SHALL read the issue of an orchestrator tab in the repo named by the `home.config` of that tab's folder.

#### Scenario: Text in the box
- **WHEN** the issue is final and the box holds text
- **THEN** the verdict is `unsure:box`, no probe character is typed, and `close` decides with its own probe

#### Scenario: The issue cannot be read
- **WHEN** the issue's comments or labels cannot be read from GitHub
- **THEN** the verdict is `unsure:issue-unreadable`

#### Scenario: A child orchestrator's tab
- **WHEN** an orchestrator tab was opened for an issue of another home
- **THEN** its issue is read in the repo named by the `home.config` of that tab's folder, and the verdict is `unsure:issue-repo` when that file names none

### Requirement: HOME-416 The orchestrator closes finished tabs
After a worker's final record and at every status, the `orchestrate` skill SHALL run `term.sh finished` and close each `closable` tab with `term.sh close` without asking only while an active standing approval of the owner for closing finished tabs is listed in the home section, naming its id in the finish text; without one it lists the closable tabs and closes on the owner's word; it never closes this way a tab outside the registry.

#### Scenario: A finished worker with the standing approval
- **WHEN** `term.sh finished` lists a worker tab as `closable` and an active standing approval allows closing finished tabs
- **THEN** the orchestrator runs `term.sh close` on it without asking and names the approval's id in its finish text

#### Scenario: A finished worker without the standing approval
- **WHEN** `term.sh finished` lists a worker tab as `closable` and no such approval is active
- **THEN** the orchestrator lists the tab as closable and closes nothing until the owner says so

### Requirement: HOME-417 A model reads what the checks could not
For a tab whose verdict is `unsure`, the `orchestrate` skill SHALL have a subagent on the `haiku` alias read that tab's screen and answer finished, not finished or unsure with one reason, and an answer of unsure once more a subagent on the `sonnet` alias; an answer of finished only allows calling `term.sh close` under HOME-416, never with `--adopt` or a flag the owner did not give and never past a refusal of `close`; a tab still unsure stays open and is listed in the status.

#### Scenario: The small model is sure
- **WHEN** a tab is `unsure:box` and the `haiku` subagent answers finished
- **THEN** the orchestrator calls `term.sh close` on it, and `close` still refuses when the box holds a real draft

#### Scenario: Both models are unsure
- **WHEN** the `haiku` and then the `sonnet` subagent answer unsure
- **THEN** the tab stays open and the status lists it with the reason

#### Scenario: A model says finished and close refuses
- **WHEN** a model answers finished and `term.sh close` exits 3
- **THEN** the tab stays open and nothing else is tried on it
