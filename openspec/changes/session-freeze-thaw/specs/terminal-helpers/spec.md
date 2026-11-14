## MODIFIED Requirements

### Requirement: HOME-063 Survey of live tabs
`term.sh survey` SHALL print one line `<tty> <pid|-> <claude|shell> <session_id|-> <cwd>` per live tab, limited with `--cwd` to session tabs running in that working directory, and `term.sh survey --json` SHALL print one JSON object per live tab holding its tty, window, tab id, pid, kind (`claude`, `codex` or `shell`), session id and where it came from, profile, session-file status, cwd, group and where it came from, whether this home registered it, its issue, its resume line (null when it cannot be reopened) and whether it is the calling session.

#### Scenario: Before launching a worker
- **WHEN** the orchestrator runs `term.sh survey --cwd <dir>`
- **THEN** it sees whether a live session already runs in that folder

#### Scenario: A tab of another tool
- **WHEN** a tab runs a session of a tool other than Claude Code
- **THEN** survey reports it as `shell`, since the helpers support Claude Code sessions only

#### Scenario: A Codex tab in the JSON survey
- **WHEN** a `codex` process runs on a tab and `term.sh survey --json` runs
- **THEN** that tab's kind is `codex` and no session id or resume line is given for it

### Requirement: HOME-106 Closing or parking the owner's own tab
`term.sh close` and `term.sh park` SHALL act on a tab missing from this home's registry only with `--adopt` and an explicit tty on which exactly one `claude` process runs and whose screen can be read, keep every other check of close and park (for close the issue check only when an issue is given), take the session id from the command line or else from the session's file, record the tab in the registry with `adopted: true` before the first keystroke, and refuse with exit 2 when `--adopt` targets a session id or a tab this home opened.

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

### Requirement: HOME-129 An adopted tab resumes with its launch flags
The resume line `term.sh` builds for a tab it did not open SHALL hold, in this order, `launch.command`, `launch.profile_flag` with the profile (from the session file's folder, else the command line, else `launch.profile.<role>`), `--model <alias>` (from the command line when it is an alias, else `launch.model`), `--dangerously-skip-permissions` only when the original command line had it, and `--resume <session id>`, dropping every other argument; a session with no known id, or with a known profile while `launch.profile_flag` is unset, gets no resume line and is never closed by park or freeze.

#### Scenario: Parking an adopted tab started with a profile and a model
- **WHEN** `launch.profile_flag` is `--profile` and `term.sh park <tty> --adopt --issue 21` runs on a tab started as `claude --profile team --model opus --resume <id>`
- **THEN** the resume command written to issue 21 is `cd <cwd> && 'claude' --profile 'team' --model 'opus' --resume <id>`

#### Scenario: Profile from the session file
- **WHEN** `launch.profile_flag` is `-p` and a tab started as `claude --model opus "<prompt>"` has its session file under the profile folder `work`
- **THEN** its resume line is `cd <cwd> && 'claude' -p 'work' --model 'opus' --resume <id>`, without the prompt

#### Scenario: Profile that cannot be passed
- **WHEN** the session file names a profile and `launch.profile_flag` is unset
- **THEN** the tab gets no resume line, and park and freeze never close it

## ADDED Requirements

### Requirement: HOME-301 Session files
`term.sh` SHALL read a live session's identity from `<dir>/<pid>.json` in the folders matched by `term.sessions_dirs` (comma-separated globs from `.local/config` only, default `${CLAUDE_CONFIG_DIR:-~/.claude}/sessions`), take the profile from the folder above `sessions` (none for `.claude`), and ignore a file whose `pid` differs from its name or that belongs to a process other than `claude`.

#### Scenario: A file for another program
- **WHEN** a session file exists for the pid of a shell
- **THEN** the shell's tab has no session id

### Requirement: HOME-302 Where a session id comes from
`term.sh` SHALL take a tab's session id from this home's registry, else its session file, else its command line, and a tab with none of them SHALL get no resume line.

#### Scenario: No session file and no id
- **WHEN** a tab runs `claude -r` and no session file exists for its process
- **THEN** `survey --json` gives it no session id and no resume line

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
After the snapshot, `term.sh freeze` SHALL open and claim one `Freeze <id>` issue in each owning home (`term.group.<g>.home`: `self` or a name of `homes.*`) with `home-log`, read it back, park the own issue of a tab bound to one, and type nothing into a tab whose record failed.

#### Scenario: The record fails
- **WHEN** creating the freeze issue fails
- **THEN** no tab receives a key and each tab of that home is listed as `kept:no-record`

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
`term.sh thaw [<id>|latest]` SHALL reopen a freeze's closed sessions and its caller in their group windows, in `term.groups` order, with their recorded resume lines and one message (re-ask an open question; read the soft checkpoint first; else continue), type nothing after the launch line, and finish each freeze issue once all its closed sessions are reopened.

#### Scenario: Open question
- **WHEN** a frozen session had a dialog open
- **THEN** its reopened tab is asked to re-ask its open question

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
