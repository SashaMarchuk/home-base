# terminal-helpers Specification

## Purpose
Optional terminal helpers let the orchestrator open, read, type into, park, resume and close session tabs on a macOS machine. They are off by default, never type into a busy tab or erase unsent text, answer only a login dialog after a check passes, and never force a session closed.

## Requirements

### Requirement: HOME-055 Off unless switched on
Every verb of `scripts/term/term.sh` SHALL exit 3 without opening or typing anything unless `terminal_helpers=on` is set, and also when it runs in a Codex session (`CODEX_THREAD_ID` set) or with `launch.command=codex`, because the helpers drive Claude Code tabs only.

#### Scenario: Helpers off
- **WHEN** `term.sh open` runs with `terminal_helpers=off`
- **THEN** it exits 3 and no tab is opened

#### Scenario: Codex orchestrator
- **WHEN** `term.sh open` runs with `terminal_helpers=on` from a Codex session or with `launch.command=codex`
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
`term.sh survey` SHALL print one line `<tty> <pid|-> <claude|shell> <session_id|-> <cwd>` per live tab, limited with `--cwd` to session tabs running in that working directory; `term.sh survey --json` prints the same tabs as JSON (HOME-321).

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
`term.sh state` SHALL print one word for a target tab: `gone` when its recorded process has ended, exit 4 with no word when the tab itself is gone or its screen cannot be read, else the first that applies of an open dialog, a heads-up notice, a running turn, no input box (`shell`), background jobs, unsent text in the box and an empty box (`idle`), while `term.sh screen` prints the tab's screen text, its last lines only with `--lines N`.

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

#### Scenario: A tab started without a session id
- **WHEN** `term.sh park <tty> --adopt --issue 21` runs on a tab started as `claude --model opus` whose session file names its session id and that session's run has a comment on issue 21
- **THEN** the session is parked under the id from its session file

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
The resume line `term.sh` builds for a tab it did not open SHALL hold only `launch.command`, `launch.profile_flag` with the profile (session file, else command line, else `launch.profile.<role>`), `--model <alias>` (command line, else `launch.model`), `--dangerously-skip-permissions` when the original had it, and `--resume <session id>`.

#### Scenario: Parking an adopted tab started with a profile and a model
- **WHEN** `launch.profile_flag` is `--profile` and `term.sh park <tty> --adopt --issue 21` runs on a tab started as `claude --profile team --model opus --resume <id>`
- **THEN** the resume command written to issue 21 is `cd <cwd> && 'claude' --profile 'team' --model 'opus' --resume <id>`

#### Scenario: Profile from the session file
- **WHEN** `launch.profile_flag` is `-p` and a tab started as `claude --model opus "<prompt>"` has its session file under the profile folder `work`
- **THEN** its resume line is `cd <cwd> && 'claude' -p 'work' --model 'opus' --resume <id>`, without the prompt

### Requirement: HOME-153 An adopted tab is bound to an issue only after its check passed
`term.sh park --adopt` and `term.sh close --adopt` SHALL record the adopted tab with no issue and set its issue only after the park checkpoint or the close's finished-issue check on that issue succeeded, while a tab bound to an issue still refuses a different `--issue`.

#### Scenario: A park that failed is tried with another issue
- **WHEN** `term.sh park <tty> --adopt --issue 21` fails at the `home-log` checkpoint and `term.sh park <tty> --adopt --issue 22` runs next on a session whose run has a comment on issue 22
- **THEN** the first call leaves the tab recorded with no issue and the second parks it under issue 22

#### Scenario: A tab already bound
- **WHEN** a tab recorded under issue 12 is closed with `--issue 13`
- **THEN** close exits 3 and nothing is typed

### Requirement: HOME-154 Parking an adopted tab needs its run on the issue
Before `term.sh park --adopt` records anything, it SHALL check that the session's run has a `home-log` comment on the issue, and otherwise exit 3 with one line telling to run `scripts/home-log start <n> --run-id <session id>` first.

#### Scenario: The owner's session never claimed the issue
- **WHEN** `term.sh park <tty> --adopt --issue 21` runs and issue 21 has no comment of that session's run
- **THEN** park exits 3 naming `scripts/home-log start 21 --run-id <session id>`, nothing is recorded and nothing is typed

### Requirement: HOME-132 Only term.sh writes the registry
A session SHALL never edit `.local/registry.json` by hand; only `term.sh` writes it.

#### Scenario: A tab is bound to the wrong issue
- **WHEN** a registry entry names the wrong issue
- **THEN** the session uses a `term.sh` command with the right `--issue` and does not edit the file

### Requirement: HOME-139 Profiles are set by saying so
When the owner says "set profile <orchestrator|worker> <name>" or "use profile <name> for workers", the `orchestrate` skill SHALL run `scripts/configure --set launch.profile.<role>=<name>` and confirm in one line, and on "show profiles" run `scripts/configure --get` for both roles.

#### Scenario: Worker profile named
- **WHEN** the owner says "use profile work for workers"
- **THEN** the orchestrator runs `scripts/configure --set launch.profile.worker=work` and replies with one line holding `launch.profile.worker=work`

### Requirement: HOME-301 Session files
`term.sh` SHALL read a live session's identity from `<dir>/<pid>.json` in the folders matched by `term.sessions_dirs` (comma-separated globs from `.local/config` only, default `${CLAUDE_CONFIG_DIR:-~/.claude}/sessions`), take the profile from the folder above `sessions` (none for `.claude`), and ignore a file whose `pid` differs from its name or that belongs to a process other than `claude`.

#### Scenario: A file for another program
- **WHEN** a session file exists for the pid of a shell
- **THEN** the shell's tab has no session id

### Requirement: HOME-302 Where a session id comes from
`term.sh` SHALL take a tab's session id from this home's registry only while the entry's pid is the live process and the session file names no other id, else from its session file, else its command line; freeze keeps a tab whose registry entry no longer matches as `kept:changed`, and a tab with no id SHALL get no resume line.

#### Scenario: No session file and no id
- **WHEN** a tab runs `claude -r` and no session file exists for its process
- **THEN** `survey --json` gives it no session id and no resume line

#### Scenario: A new session in a reused tab
- **WHEN** the session this home opened in a tab exited and a new `claude` session runs in the same tab
- **THEN** freeze sends that tab no key and lists it as `kept:changed`

### Requirement: HOME-303 The calling session is never touched
`term.sh` SHALL find the calling session by two signals, the first `claude` process above its own process and `CLAUDE_CODE_SESSION_ID` matched in the session files, leave a tab found by either untouched with its resume line recorded, and exit 3 with nothing touched when `freeze --all`, `--group` or `--window` runs inside a session whose tab neither signal finds.

#### Scenario: Freeze all from the orchestrator
- **WHEN** the orchestrator runs `term.sh freeze --all --hard`
- **THEN** its own tab is listed as `caller (left open)` with its resume line and receives no key

#### Scenario: Calling tab not found
- **WHEN** `CLAUDE_CODE_SESSION_ID` is set, no session file names it and no `claude` process is above `term.sh`
- **THEN** `freeze --all` exits 3 and no tab receives a key

### Requirement: HOME-304 The group of a tab
`term.sh` SHALL read `term.groups` and `term.group.<g>.cwd|home` from `.local/config` only and give a tab the group recorded in the registry, else the group with the longest matching folder prefix, else `general`; `open --group <g>` records that group, and an unknown group exits 2 with nothing opened.

#### Scenario: Group keys in the committed file
- **WHEN** `term.groups` is set only in `home.config`
- **THEN** it is ignored

#### Scenario: Longest prefix
- **WHEN** one group names a folder and another group names a folder inside it
- **THEN** a tab working in the inner folder belongs to the second group

### Requirement: HOME-305 The window of a group
`term.sh open` SHALL put a tab of a group in the window holding most live tabs of that group, else in the window cached in `.local/windows.json` while it exists and holds no other group's tab, else in a new window that it caches; with no `term.groups` and no `--group`, it uses the current window.

#### Scenario: A live tab of the group
- **WHEN** a tab of group `g1` is live in window 7 and `term.sh open <a folder of g1>` runs
- **THEN** the new tab opens in window 7 and the registry records group `g1` and window 7

#### Scenario: A cached window now used by another group
- **WHEN** `.local/windows.json` caches window 5 for `g1` and window 5 now holds a `g2` tab
- **THEN** a `g1` tab opens in a new window

### Requirement: HOME-306 Snapshot before the first key
`term.sh freeze` SHALL read every selected tab (screen, state, session file, an open dialog's question and options) and write `.local/freeze/<id>.json` in this home before any key reaches any tab.

#### Scenario: Order
- **WHEN** a freeze closes a tab
- **THEN** the snapshot file and the freeze issue exist when `/exit` is typed into it

### Requirement: HOME-307 One freeze issue per owning home
After the snapshot, `term.sh freeze` SHALL open and claim one `Freeze <id>` issue in each owning home (`term.group.<g>.home`: `self` or a name of `homes.*`) with `home-log`, read it back, park the own issue of a worker or owner tab bound to one (with its question only when its group belongs to this home), and type nothing into a tab whose record failed.

#### Scenario: The record fails
- **WHEN** creating the freeze issue fails
- **THEN** no tab receives a key and each tab of that home is listed as `kept:no-record`

#### Scenario: An orchestrator tab with a child's issue
- **WHEN** an orchestrator tab opened for a child home's issue is frozen
- **THEN** no issue of this home with that number is written

### Requirement: HOME-308 Freeze selectors
`term.sh freeze` SHALL take one selector (`--all`, `--group <g>`, `--window <group | window id | front>`, or ttys and session ids, never a title), drop `--except` targets, exit 2 for an unknown group or window and exit 4 for a target with no live tab, touching nothing; `--dry-run` prints the plan and touches nothing.

#### Scenario: Unknown window
- **WHEN** `term.sh freeze --window w99 --hard` runs and no tab is in that window
- **THEN** it exits 2 and no snapshot is written

### Requirement: HOME-309 What freeze never touches
`term.sh freeze` SHALL act only on tabs with exactly one `claude` process and a resume line, list other tools' tabs, the caller and sessions without a resume line as kept with no key, exit 3 when nothing can be acted on, and exit 3 while `.local/freeze.lock` is held, never removing another run's lock.

#### Scenario: A Codex tab named alone
- **WHEN** `term.sh freeze <tty of a codex tab> --hard` runs
- **THEN** it exits 3 and nothing is typed

#### Scenario: A second freeze at once
- **WHEN** `.local/freeze.lock` exists and a freeze starts
- **THEN** it exits 3, nothing is typed and the lock stays

### Requirement: HOME-310 Two signals before a key
`term.sh freeze` SHALL send a key to a tab only while its session file's status and its screen agree: `idle` with an idle, draft, background-job or notice screen, `busy` with a running turn, `waiting` with a dialog.

#### Scenario: Signals disagree
- **WHEN** the screen shows an idle box and the session file says `busy`
- **THEN** the tab receives no key and is kept

### Requirement: HOME-311 Hard close per state
`freeze --hard` SHALL type `/exit` into an idle, empty box and check the process is gone, clear a suggestion found by the ghost probe, keep a tab with a real draft, press Esc once on a dialog already recorded (never an option; kept if it stays open), keep a running turn after `term.freeze.hard_grace` seconds without any key, and report a process that outlives `/exit` with exit 5, never signalling it.

#### Scenario: Running turn
- **WHEN** a tab's turn is still running after the grace time
- **THEN** no Esc or other key is sent and the tab is listed as `kept:busy`

#### Scenario: Unsent draft
- **WHEN** the box holds text the owner typed
- **THEN** only the probe character and its backspace are typed, the text stays, and the tab is listed as `kept:draft`

### Requirement: HOME-312 Conservative freeze values and continuing
`term.sh freeze` SHALL ignore, with a note, a `term.freeze.drafts` value other than `skip` and a `term.freeze.busy` value other than `wait`, and `freeze --continue <id>` SHALL act again on the tabs kept for a running turn, disagreeing signals, a draft or a soft timeout.

#### Scenario: A hand-written opt-in
- **WHEN** `.local/config` holds `term.freeze.busy=interrupt` and a tab's turn is running
- **THEN** freeze sends it no key

### Requirement: HOME-313 Unmapped tabs and other homes' text
A tab whose group comes only from the `general` fallback SHALL keep its question, name and folder in this home's snapshot and appear in the freeze issue as one pointer line, and a question of a tab whose group belongs to another home SHALL go only into that home's freeze issue.

#### Scenario: An unmapped tab with an open question
- **WHEN** a tab in a folder no group names shows a dialog and `freeze --all --hard` runs
- **THEN** this home's freeze issue holds only a pointer line for it, and its question is in no issue

#### Scenario: A tab of another home
- **WHEN** a tab of a group whose home is `peer` holds an open question
- **THEN** the question is in `peer`'s freeze issue and not in this home's

### Requirement: HOME-314 Soft close prompt
`freeze --soft` SHALL type one prompt per tab only while both signals say idle and the box is empty, never interrupting a turn or touching a dialog, asking the session to pause and write `.local/freeze/<id>/<session id>.md` ending with the line `nonce: <N>`, `N` random per tab.

#### Scenario: Busy tab
- **WHEN** a tab's turn runs for the whole soft timeout
- **THEN** no key is sent and the tab is listed as `kept:soft-timeout`

### Requirement: HOME-315 Soft close is done only by the session's own file
`freeze --soft` SHALL close a tab only once its checkpoint file exists, ends with its exact nonce line and the session file says idle; at `term.freeze.soft_timeout` it keeps the tab, while `--soft-then-hard` gives it the hard close; with no mode, freeze takes `term.freeze.default_mode` (default `soft-then-hard`).

#### Scenario: Only the echo of the prompt
- **WHEN** the prompt shows on screen but no file is written
- **THEN** no `/exit` is typed and the tab is listed as `kept:soft-timeout`

#### Scenario: Wrong nonce
- **WHEN** the file ends with another nonce
- **THEN** no `/exit` is typed

### Requirement: HOME-316 Soft checkpoints in the record
After a freeze, `term.sh` SHALL copy a mapped tab's soft checkpoint, without its nonce line, into its home's freeze issue with the outcomes, keep an unmapped tab's checkpoint local, and write the outcomes alone when the checkpoint text is refused as sensitive.

#### Scenario: Unmapped checkpoint
- **WHEN** an unmapped tab writes its soft checkpoint
- **THEN** its text is in no issue

### Requirement: HOME-317 Thaw reopens by group
`term.sh thaw [<id>|latest]` SHALL reopen a freeze's closed sessions and its caller in their group windows, in `term.groups` order, with their recorded resume lines and one message (re-ask an open question; read the soft checkpoint first; else continue), type nothing after the launch line, and finish each freeze issue once each of its sessions is reopened or live already.

#### Scenario: Open question
- **WHEN** a frozen session had a dialog open
- **THEN** its reopened tab is asked to re-ask its open question

#### Scenario: The caller stayed open
- **WHEN** the only session of a freeze issue not reopened is the caller, still live
- **THEN** thaw finishes that freeze issue

### Requirement: HOME-318 What thaw skips
`term.sh thaw` SHALL skip a session that is live already, an entry that was not closed, and a session whose transcript is not on this machine, printing its resume line.

#### Scenario: Already live
- **WHEN** a frozen session's id is live in a tab
- **THEN** thaw does not launch it again

### Requirement: HOME-319 Thaw stops, queues and reads the issue
`term.sh thaw` SHALL check memory before each tab and on a refusal stop with exit 3 naming `thaw --continue <id>`, queue workers at `term.max_workers`, and with `--issue OWNER/REPO#N` read the freeze-data block when the snapshot is missing.

#### Scenario: Low memory
- **WHEN** free memory is below `term.min_free_pct`
- **THEN** thaw opens nothing more, exits 3 and prints how many are left and `thaw --continue <id>`

### Requirement: HOME-320 Closing sessions the owner named
The `orchestrate` skill SHALL close or freeze only sessions the owner named, ask once before closing or freezing several at once and never offer to freeze every session; only once the real-tab check of freeze and thaw has passed SHALL a freeze, thaw or close whose scope the owner named run without a confirmation.

#### Scenario: Before the real-tab check
- **WHEN** the owner says to close the sessions of one group and the real-tab check has not passed
- **THEN** the orchestrator asks once before freezing them

### Requirement: HOME-321 Survey in JSON
`term.sh survey --json` SHALL print one JSON object per live tab with its tty, window, tab id, pid, kind (`claude`, `codex` or `shell`), session id and its source, profile, session-file status, cwd, group and its source, registration, issue, resume line and whether it is the calling session.

#### Scenario: A Codex tab
- **WHEN** a `codex` process runs on a tab
- **THEN** its kind is `codex` and it has no session id or resume line

### Requirement: HOME-322 A session that cannot be reopened is never closed
A session with no known id, or whose profile is known while `launch.profile_flag` is unset, SHALL get no resume line, and park and freeze SHALL never close it.

#### Scenario: Profile that cannot be passed
- **WHEN** the session file names a profile and `launch.profile_flag` is unset
- **THEN** the tab gets no resume line, and park and freeze never close it
