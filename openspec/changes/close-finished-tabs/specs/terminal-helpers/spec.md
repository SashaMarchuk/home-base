## MODIFIED Requirements

### Requirement: HOME-320 Closing sessions the owner named
The `orchestrate` skill SHALL close or freeze only sessions the owner named, ask once before closing or freezing several at once and never offer to freeze every session, except for finished tabs under HOME-416; only once the real-tab check of freeze and thaw has passed SHALL a freeze, thaw or close whose scope the owner named run without a confirmation.

#### Scenario: Before the real-tab check
- **WHEN** the owner says to close the sessions of one group and the real-tab check has not passed
- **THEN** the orchestrator asks once before freezing them

## ADDED Requirements

### Requirement: HOME-414 Which tabs are finished
`term.sh finished` SHALL print `<tty> <session id> <issue|-> <verdict>` for every open tab of this home's registry (`--json`: one object per tab, with the repo of its issue), the verdict being `closable`, `keep:<reason>` or `unsure:<what could not be read>` from the checks of `close` (HOME-061) in their order, and SHALL send no key, write no file and close nothing.

#### Scenario: A finished worker
- **WHEN** a worker tab's issue has a final `home-log` comment and no owner label, and its screen shows an empty box and nothing running
- **THEN** `finished` prints `closable` for it

#### Scenario: Nothing is touched
- **WHEN** `finished` runs over tabs with a notice, a dialog, a draft and an empty box
- **THEN** no tab receives a key and the registry is unchanged

### Requirement: HOME-415 Closable and kept tabs
`term.sh finished` SHALL say `closable` only when the issue has a final `home-log` comment and no owner label and the session's process is gone or its screen shows no dialog, running turn or background job and an empty input box, and `keep:<reason>` for a tab that is gone, the calling session, no issue, no final comment, an owner label, a dialog, a running turn, background work or a Codex tab without its thread id.

#### Scenario: An open question
- **WHEN** the tab's issue carries the owner label
- **THEN** the verdict is `keep:owner-question`

#### Scenario: The session ended on its own
- **WHEN** the issue is final and the session's process is gone while its tab is still open
- **THEN** the verdict is `closable`

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
