# terminal-helpers Specification

## Purpose
Optional terminal helpers let the orchestrator open, read, type into, park, resume and close session tabs on a macOS machine. They are off by default, never type into a busy tab or erase unsent text, answer only a login dialog after a check passes, and never force a session closed.

## Requirements

### Requirement: HOME-055 Off unless switched on
Every verb of `scripts/term/term.sh` SHALL exit 3 without opening or typing anything unless `terminal_helpers=on` is set.

#### Scenario: Helpers off
- **WHEN** `term.sh open` runs with `terminal_helpers=off`
- **THEN** it exits 3 and no tab is opened

### Requirement: HOME-056 Tabs addressed by tty or session id
`term.sh` SHALL accept as a target only a tty or a session id recorded in `.local/registry.json`, refusing a tab title with exit 2, and verify the tab against its recorded tab id and process id before acting.

#### Scenario: Reused process id
- **WHEN** the recorded process id now belongs to another command
- **THEN** it exits 3 and does nothing

#### Scenario: Tab title as target
- **WHEN** a verb is given a tab title as its target
- **THEN** it exits 2 and does nothing

### Requirement: HOME-057 Safe typing
`term.sh send` SHALL type one line only when the tab shows no dialog, no running turn and an empty input box, dismissing a heads-up notice once first, treating text in the box as a suggestion only when a single probe character comes back alone, and pressing a swallowed Enter once more and never twice.

#### Scenario: Unsent text in the box
- **WHEN** the input box holds text the owner typed
- **THEN** the text is kept and `send` waits, exiting 5 at its timeout with nothing sent

#### Scenario: Login dialog after the check
- **WHEN** `send --after <check command>` runs, the check passes and the tab shows a dialog whose question matches `term.login_dialog_re` and that has a free-text row
- **THEN** the screen is read again and the text is typed into that free-text row

#### Scenario: Any other dialog
- **WHEN** the open dialog is not a login dialog, has no free-text row, or `--after` was not given
- **THEN** `send` does not answer it and waits

### Requirement: HOME-058 Opening a tab
`term.sh open` SHALL refuse with exit 3 when free memory is below `term.min_free_pct` (default 20) or cannot be read while that value is not 0, when the open worker tabs reach `term.max_workers` (default 4), or when a launch value is invalid, and otherwise print `<session_id> <tty> <pid>`.

#### Scenario: Worker cap
- **WHEN** four worker tabs are open and the cap is 4
- **THEN** opening a fifth worker exits 3

#### Scenario: Pinned model version
- **WHEN** `launch.model` names a pinned model version
- **THEN** open exits 3

#### Scenario: Memory cannot be read
- **WHEN** the free-memory percentage cannot be read and `term.min_free_pct` is not 0
- **THEN** open exits 3 and no tab is opened

### Requirement: HOME-059 Park
`term.sh park` SHALL work only on a running session this home opened with a session id, refuse with exit 3 when a turn is running or unsent text is in the box, record an open dialog's question as the open question and cancel the dialog without answering it, and write the open question and the resume command to the issue through `home-log` before the session exits.

#### Scenario: Park for a hard limit
- **WHEN** a worker tab is parked with `--issue 8`
- **THEN** issue 8 carries `status:parked` and its comment holds the resume command

#### Scenario: Busy session
- **WHEN** park targets a session whose turn is still running
- **THEN** it exits 3 and the turn is not interrupted

#### Scenario: Dialog open at park
- **WHEN** the session shows a dialog when it is parked
- **THEN** the dialog's question is written to the issue as the open question and the dialog is cancelled, not answered

### Requirement: HOME-060 Resume
`term.sh resume <session_id>` SHALL reopen only a closed, resumable session from its recorded resume command, respect the worker cap, and send the session the one message HOME-122 sets.

#### Scenario: Session still open
- **WHEN** the session id is still open in a tab
- **THEN** resume exits 3

### Requirement: HOME-061 Close only a finished session
`term.sh close` SHALL close only a tab this home opened, for an issue given with `--issue` or recorded at open (exit 2 without one), whose issue on GitHub has a final `home-log` comment and no owner label, and whose screen shows no dialog, no running turn, no background job and an empty input box, refusing with exit 3 otherwise or when the issue cannot be read, and then verify that the session's process is gone.

#### Scenario: No final comment
- **WHEN** the tab's issue has no final `home-log` comment
- **THEN** close exits 3 and the tab stays open

#### Scenario: Question waiting on the owner
- **WHEN** the tab's issue carries the owner label
- **THEN** close exits 3 and the tab stays open

#### Scenario: Issue cannot be read
- **WHEN** the issue's comments or labels cannot be read from GitHub
- **THEN** close exits 3 and the tab stays open

### Requirement: HOME-062 No force-close
`term.sh` SHALL end a session only by typing its exit command, never signal a session's process, and write files only under `.local/`.

#### Scenario: Lingering session
- **WHEN** a session's process does not exit after `/exit`
- **THEN** close exits 5, no process is signalled and the tab is left as it is

### Requirement: HOME-063 Survey of live tabs
`term.sh survey` SHALL print one line `<tty> <pid|-> <claude|shell> <session_id|-> <cwd>` per live tab, limited with `--cwd` to session tabs running in that working directory.

#### Scenario: Before launching a worker
- **WHEN** the orchestrator runs `term.sh survey --cwd <dir>`
- **THEN** it sees whether a live session already runs in that folder

#### Scenario: A tab of another tool
- **WHEN** a tab runs a session of a tool other than Claude Code
- **THEN** survey reports it as `shell`, since the helpers support Claude Code sessions only

### Requirement: HOME-064 Without helpers
With terminal helpers off, the orchestrator SHALL give each worker brief to the owner as a ready-to-paste prompt or run the task in its own session, and open nothing.

#### Scenario: Helpers off on Linux
- **WHEN** a ready issue is dispatched on a machine without helpers
- **THEN** the owner receives the brief to paste into a new session

### Requirement: HOME-071 Launch values from the machine file only
`term.sh open` SHALL build the launch command only from `.local/config`, never from `home.config`: `launch.command` (one command word, default `claude`), `launch.profile_flag` followed by `launch.profile.<role>` when both are set, and `--model <launch.model>` when that alias is set, refusing with exit 3 a command, flag or model of another shape, while `term.sh resume` reuses the resume command recorded at open.

#### Scenario: Launch value in the committed file
- **WHEN** `launch.command` is set only in `home.config`
- **THEN** open launches the default command `claude`

#### Scenario: Profile flag without a profile
- **WHEN** `launch.profile_flag` is set and `launch.profile.worker` is empty
- **THEN** a worker tab is launched without a profile

#### Scenario: Command with arguments
- **WHEN** `launch.command` holds more than one word
- **THEN** open exits 3 and no tab is opened

### Requirement: HOME-072 Reading a tab
`term.sh state` SHALL print one word for a target tab: `gone` when its recorded process has ended, else the first that applies of an open dialog, a heads-up notice, a running turn, no input box (`shell`), background jobs, unsent text in the box and an empty box (`idle`), while `term.sh screen` prints the tab's screen text, its last lines only with `--lines N`.

#### Scenario: Recorded process ended
- **WHEN** the recorded process of a registered tab no longer runs
- **THEN** `state` prints `gone`

#### Scenario: Empty box
- **WHEN** the tab shows an empty input box and nothing else is open or running
- **THEN** `state` prints `idle`

### Requirement: HOME-106 Closing or parking the owner's own tab
`term.sh close` and `term.sh park` SHALL act on a tab missing from this home's registry only with `--adopt` and an explicit tty on which exactly one `claude` process runs and whose screen can be read, keep every other check of close and park (for close the issue check only when an issue is given), record the tab in the registry with `adopted: true` before the first keystroke, and refuse with exit 2 when `--adopt` targets a session id or a tab this home opened.

#### Scenario: Owner asks to close a tab opened by hand
- **WHEN** the owner asks to close a tab the owner opened by hand and `term.sh close <tty> --adopt` runs on it while its box is empty
- **THEN** the tab is recorded with `adopted: true`, its session exits and no process is signalled

#### Scenario: Owner's tab without the flag
- **WHEN** close targets the tty of a tab missing from the registry without `--adopt`
- **THEN** close exits 3 and nothing is typed

#### Scenario: Two sessions on one tty
- **WHEN** two `claude` processes run on the tty given with `--adopt`
- **THEN** close exits 3 and nothing is typed

### Requirement: HOME-107 Relaying the owner's words into a dialog
`term.sh send` SHALL type the owner's words given with `--relay` only into the free-text row of a dialog open on that tab and never pick a listed option, press Enter only once the words show on screen, press Esc once for `--cancel-dialog` and check the dialog closed, and refuse with exit 3 an `--after` check that proves nothing (empty, `true`, `:`, `exit 0`, `echo ...`, `test 1`).

#### Scenario: Owner answers a waiting dialog
- **WHEN** a session shows a dialog with a free-text row and `term.sh send <tty> --relay "use the release branch"` runs
- **THEN** the free-text row is picked, the words are typed and shown on screen, and Enter is pressed once

#### Scenario: Dialog without a free-text row
- **WHEN** `--relay` targets a tab with no open dialog, or one with only listed options
- **THEN** send exits 3 and nothing is typed

#### Scenario: Words not shown
- **WHEN** the typed words do not appear on screen
- **THEN** send exits 3 and Enter is not pressed

#### Scenario: Owner says to dismiss the dialog
- **WHEN** `term.sh send <tty> --cancel-dialog` runs on a tab with an open dialog
- **THEN** Esc is pressed once and the dialog is closed, not answered

#### Scenario: Check that proves nothing
- **WHEN** `send --after true` runs instead of a check that proves the login, e.g. a CLI identity call
- **THEN** send exits 3 and nothing is typed

### Requirement: HOME-122 The resume message
`term.sh resume` SHALL send `--message <text>` when given, no message with `--silent`, and otherwise ask the session to re-ask its open question only when the run's `home-log` comment on the issue holds "Open question for the owner", else to continue where it stopped, and SHALL refuse with exit 2 when both options or an empty text are given.

#### Scenario: Open question on the issue
- **WHEN** the run's comment holds "Open question for the owner" and `term.sh resume <session_id>` runs
- **THEN** the session is asked to re-ask its open question

#### Scenario: No open question
- **WHEN** the run's comment holds no open question
- **THEN** the session is asked to continue where it stopped

#### Scenario: A message by class
- **WHEN** `term.sh resume <session_id> --message "The timer fired; run the next step."` runs
- **THEN** that text is the only message sent, and `--silent` sends none

### Requirement: HOME-129 An adopted tab resumes with its launch flags
When `term.sh` adopts a tab whose command line names a session id, the resume command it records SHALL keep that command line's command, its configured profile flag with the value and its `--model <alias>`, followed by `--resume <session id>`.

#### Scenario: Parking an adopted tab started with a profile and a model
- **WHEN** `launch.profile_flag` is `-a` and `term.sh park <tty> --adopt --issue 21` runs on a tab started as `claude -a personal --model opus --resume <id>`
- **THEN** the resume command written to issue 21 is `cd <cwd> && 'claude' -a 'personal' --model 'opus' --resume <id>`

### Requirement: HOME-132 Only term.sh writes the registry
A session SHALL never edit `.local/registry.json` by hand; only `term.sh` writes it.

#### Scenario: A tab is bound to the wrong issue
- **WHEN** a registry entry names the wrong issue
- **THEN** the session uses a `term.sh` command with the right `--issue` and does not edit the file
