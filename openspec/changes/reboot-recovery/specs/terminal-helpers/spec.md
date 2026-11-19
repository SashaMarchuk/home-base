## ADDED Requirements

### Requirement: HOME-460 A reused tty never names a dead session
`term.sh survey` SHALL print the registry's session id for a tab only while an open entry names that tty, that tab (or no tab yet) and the live `claude` process of the tab, and `-` otherwise, SHALL list a Codex tab as `<tty> <pid> codex <session id> <cwd>` only while a Codex registry entry names its one `codex` process and as a shell line otherwise, and `term.sh freeze` SHALL mark or close a registry entry only by its tty and its session id, never another open entry of the same tty.

#### Scenario: A new session on a reused tty
- **WHEN** an open registry entry names `ttys002` with another tab id and a process that is gone, and a new `claude` session runs on `ttys002`
- **THEN** `term.sh survey` prints `-` as that tab's session id

#### Scenario: A registered Codex tab
- **WHEN** a Codex tab's registry entry names its tab and its one `codex` process
- **THEN** `term.sh survey` prints its pid, `codex` and its session id

#### Scenario: Freeze on a reused tty
- **WHEN** the new session on a reused tty is frozen
- **THEN** its own entry is closed and the old entry of that tty stays as it was

### Requirement: HOME-461 Lost sessions
`term.sh reconcile` SHALL treat an open registry entry as alive only while a live tab has its recorded tab id on its recorded tty and the session runs there (its recorded process, or a `claude` or `codex` process on that tty whose command line carries its session id), mark it `lost: <time>` (never `closed`) only when its tab is gone or no longer runs it and that process is gone, and move its tty, tab and pid to `lost_*` fields, one `LOST` line per change (HOME-475).

#### Scenario: After a reboot
- **WHEN** the tab and the process of an open entry are both gone
- **THEN** reconcile marks it lost, keeps its issue and prints one line

#### Scenario: A window restored with the same tab ids
- **WHEN** iTerm2 restored a window after a restart, so a live tab has the entry's tab id on its tty but only a fresh shell runs there
- **THEN** reconcile marks the entry lost

#### Scenario: Resumed by hand in its own tab
- **WHEN** the entry's recorded process is gone and `claude --resume <its id>` runs on its tty in its tab
- **THEN** reconcile leaves the entry open

#### Scenario: A second run
- **WHEN** reconcile runs again with nothing changed
- **THEN** it prints nothing and the registry is unchanged

### Requirement: HOME-475 Reconcile output and dry run
`term.sh reconcile` SHALL print one `LOST <session id> <tty>` line per entry it marks, change nothing on a second run with nothing changed, and with `--dry-run` print the plan and write nothing.

#### Scenario: Dry run
- **WHEN** `term.sh reconcile --dry-run` runs while two entries would be marked lost
- **THEN** it prints two `PLAN lost` lines and the registry is unchanged

### Requirement: HOME-467 Silence never marks a session lost
`term.sh reconcile` SHALL leave an entry whose tab is gone while its process still runs, and an entry with no tab or no process recorded, and exit 3 marking nothing when the terminal's tabs or the process list cannot be read or no tab is live at all.

#### Scenario: One signal only
- **WHEN** an entry's tab is gone and its process still runs on its tty
- **THEN** reconcile leaves it open

#### Scenario: The tabs cannot be read
- **WHEN** the terminal's tabs cannot be read
- **THEN** reconcile exits 3 and the registry is unchanged

### Requirement: HOME-462 Who marks sessions lost
`term.sh survey`, `finished` and the status SHALL never write the registry; `term.sh adopt` and `term.sh reopen` SHALL run the reconcile pass first. A lost entry SHALL be matched by no tty, and `resume` of it SHALL exit 3 naming `term.sh reopen <session id>`.

#### Scenario: Survey after a reboot
- **WHEN** `term.sh survey` and `term.sh finished` run while entries' tabs and processes are gone
- **THEN** the registry is unchanged

#### Scenario: Resume of a lost session
- **WHEN** `term.sh resume <id>` names a lost entry
- **THEN** it exits 3, opens nothing and names `term.sh reopen <id>`

### Requirement: HOME-463 Adopting a tab the home did not open
`term.sh adopt <tty>...` SHALL record a live tab this home did not open, typing nothing, with `adopted: true`, role `owner`, its session id, resume line (with its profile and model), cwd, window, profile, model, group (`--group`, else the cwd rules) and `--issue N` (with `--repo`) when given. An adopted tab keeps every protection: `close` and `park` need `--adopt` on it and `finished` keeps it.

#### Scenario: A tab opened by hand
- **WHEN** `term.sh adopt ttys004` runs on a tab the owner started with `claude --model opus`
- **THEN** the registry holds it as adopted with its session id and resume line, and no key reached the tab

### Requirement: HOME-468 What adopt skips
`term.sh adopt` SHALL skip a tab with no session id, with more than one session process, or registered already, take over the last lost or closed entry of the same session id instead of adding a second one, and exit 3 when a named tab was skipped and 4 when a named tty has no live tab; `adopt --all` SHALL adopt every live `claude` tab not registered yet except the calling session's own, which is adopted only when its tty is named.

#### Scenario: Adopt all
- **WHEN** `term.sh adopt --all` runs from an orchestrator with two hand-opened tabs and one registered tab
- **THEN** the two tabs are adopted, the registered tab and the orchestrator's own tab are not

#### Scenario: No session id
- **WHEN** the tab runs `claude -r` and no session file names its id
- **THEN** adopt exits 3 and records nothing

#### Scenario: A lost session running again
- **WHEN** a lost session was started again by hand and its tab is adopted
- **THEN** its one entry names the new tab and is no longer lost

### Requirement: HOME-470 Adopt follows a session resumed by hand in its own tab
`term.sh adopt <tty>` SHALL update the PID (and match) of an open entry that names that tty and tab and whose recorded process is dead, or that has no tty and no PID (a reservation whose tab opened unrecorded), when the same session id runs on that tty, keeping its role, issue and `adopted` value, print `UPDATED <tty> <session id>` and type nothing; while the recorded process runs it SHALL skip the tab.

#### Scenario: A crashed worker resumed by hand
- **WHEN** a worker's process died and the owner ran `claude --resume <its id>` in the same tab
- **THEN** adopt records the new PID on the worker's one entry, which stays a worker of its issue

### Requirement: HOME-464 Reopening lost sessions
`term.sh reopen [--lost | <session id>...]` SHALL reopen lost entries (all, or the ids given) in `term.groups` order, each in its group's window as `open` and `thaw` pick it, with its recorded resume line and one message: `--message`, else a re-ask of the open question when the run's last `home-log` comment on its issue holds one, else a note that it was reopened after a restart; it types nothing after the launch line.

#### Scenario: After a reboot
- **WHEN** three sessions of two groups are lost and `term.sh reopen --lost` runs
- **THEN** the two sessions of one group open in one window, the third in another, each with its resume line

#### Scenario: An open question
- **WHEN** a lost worker's last `home-log` comment holds `- Open question for the owner: ...`
- **THEN** its message asks it to re-ask that question with the ask tool

### Requirement: HOME-469 What reopen records
`term.sh reopen` SHALL record a reopened session's new tty, tab and pid and clear `lost`, leave the entry lost when its tab did not open, name a tab that opened while the registry could not record it with its tty (never as not opened, and not marked lost again), and with `--dry-run` print the plan and write and open nothing.

#### Scenario: The tab does not open
- **WHEN** opening the tab fails
- **THEN** the entry stays lost and the next `reopen --lost` tries it again

#### Scenario: Dry run
- **WHEN** `term.sh reopen --lost --dry-run` runs
- **THEN** it prints one `PLAN` line per session, opens no tab and leaves the registry unchanged

### Requirement: HOME-465 What reopen skips
`term.sh reopen` SHALL skip a session whose id runs already (in `survey --json` or after `--resume` or `--session-id` on a process's command line), a Codex entry and an entry with no resume line and no recorded profile or model (a line is rebuilt only from those recorded fields, see HOME-474), name a given id that is not lost, check memory before each tab and stop with exit 3 on a refusal, and queue workers at `term.max_workers`, leaving them lost.

#### Scenario: Reopened by hand already
- **WHEN** a lost session runs again as `claude --resume <id>` in another tab
- **THEN** reopen does not launch it and says it runs already

#### Scenario: Low memory
- **WHEN** free memory is below `term.min_free_pct`
- **THEN** reopen opens nothing, exits 3 and names `term.sh reopen --lost`

### Requirement: HOME-471 A lost entry can be dropped
`term.sh forget <session id> [--reason TEXT]` SHALL close one lost registry entry with `closed_reason: "forgotten[: <reason>]"`, clearing `lost` and keeping its issue and `lost_tty`, typing nothing and opening nothing, SHALL refuse with exit 3 an entry that is not lost and exit 4 an id that names no open entry, and a forgotten entry SHALL never be reopened by `term.sh reopen`.

#### Scenario: Work finished by hand
- **WHEN** the owner finished a lost worker's task by hand and `term.sh forget <its id>` runs
- **THEN** its entry is closed with the reason and `term.sh reopen --lost` does not open it

#### Scenario: A live session
- **WHEN** `term.sh forget` names an open entry that is not lost
- **THEN** it exits 3 and the registry is unchanged

### Requirement: HOME-472 Reopen never revives finished or taken-over work
`term.sh reopen`, `--dry-run` included, SHALL read each lost entry's issue (its recorded repo, else the orchestrator's or this home's) and skip the entry, naming why and `term.sh forget`, when the issue is closed, its run's claim comment says `final` or `released`, the last claim comment (a `delegated` hand-off note is none) is of another run, or the issue cannot be read; an entry with no issue is not checked.

#### Scenario: The issue was closed
- **WHEN** a lost worker's issue was closed while its tab was gone
- **THEN** reopen skips it, opens no tab and the entry stays lost

#### Scenario: GitHub cannot be read
- **WHEN** the issue of a lost entry cannot be read
- **THEN** reopen skips that entry with the reason and reopens the others

### Requirement: HOME-473 One reopen at a time
`term.sh reopen` without `--dry-run` SHALL hold the lock `freeze` and `thaw` use for its whole run, so a second `reopen`, `freeze` or `thaw` exits 3, and SHALL reserve each entry under the registry lock only while it is still lost and open, skipping one that another run reopened, adopted or closed meanwhile.

#### Scenario: Two reopens at once
- **WHEN** a second `term.sh reopen --lost` starts while the first is opening tabs
- **THEN** the second exits 3 and every lost session is launched once

#### Scenario: Adopted meanwhile
- **WHEN** a lost entry is taken over by adopt after reopen listed it and before reopen reserves it
- **THEN** reopen skips it and opens no tab for it

### Requirement: HOME-474 The profile and model come back
`term.sh adopt` SHALL print a `NOTE <tty>` line when the session runs under a profile that cannot be passed because `launch.profile_flag` is empty, and `term.sh reopen` SHALL rebuild a resume line that is missing or lacks the entry's recorded profile or model from the recorded session id, cwd, profile and model only, keeping `--dangerously-skip-permissions`, and never drop a recorded profile it cannot pass. The profile itself comes from HOME-301.

#### Scenario: A sessions folder shared by two profiles
- **WHEN** a session's file lies under one profile's folder while its process runs with `CLAUDE_CONFIG_DIR` of another profile
- **THEN** adopt records the profile of `CLAUDE_CONFIG_DIR` and its resume line passes that profile

#### Scenario: No profile flag
- **WHEN** a tab running under a profile is adopted while `launch.profile_flag` is empty
- **THEN** adopt records it with no resume line and prints a `NOTE` saying reopen cannot bring it back until the flag is set

#### Scenario: Adopted before the flag was set
- **WHEN** an adopted entry has no resume line, its profile and model are recorded and `launch.profile_flag` is set now
- **THEN** reopen launches it with that profile and model

### Requirement: HOME-466 Regroup is a plan only
`term.sh regroup` SHALL print one `MOVE <tty> <session id> group <g>: window <w> -> <w2>` line per registered live tab outside the window holding most of its group's tabs and move nothing, since the iTerm2 AppleScript backend cannot move a tab; with `--dry-run` it exits 0, without it exits 3 saying nothing was moved.

#### Scenario: A tab in another group's window
- **WHEN** two tabs of `g1` are in window 1 and one in window 2
- **THEN** regroup prints the move of the third to window 1 and no tab changes window

## MODIFIED Requirements

### Requirement: HOME-153 An adopted tab is bound to an issue only after its check passed
`term.sh park --adopt` and `term.sh close --adopt` SHALL record the adopted tab with no issue and set its issue only after the park checkpoint or the close's finished-issue check on that issue succeeded, while a tab bound to an issue still refuses a different `--issue`; `term.sh adopt --issue N`, which types and closes nothing, records the issue the owner named at once, and park and close of that tab still run their checks on it.

#### Scenario: A park that failed is tried with another issue
- **WHEN** `term.sh park <tty> --adopt --issue 21` fails at the `home-log` checkpoint and `term.sh park <tty> --adopt --issue 22` runs next on a session whose run has a comment on issue 22
- **THEN** the first call leaves the tab recorded with no issue and the second parks it under issue 22

#### Scenario: A tab already bound
- **WHEN** a tab recorded under issue 12 is closed with `--issue 13`
- **THEN** close exits 3 and nothing is typed

#### Scenario: Adopted with the owner's issue
- **WHEN** `term.sh adopt <tty> --issue 12` runs
- **THEN** the entry names issue 12 and no key reached the tab

### Requirement: HOME-063 Survey of live tabs
`term.sh survey` SHALL print one line `<tty> <pid|-> <claude|codex|shell> <session_id|-> <cwd>` per live tab (`codex` only for a Codex tab whose registry entry names its one `codex` process, see HOME-460), limited with `--cwd` to session tabs running in that working directory; `term.sh survey --json` prints the same tabs as JSON (HOME-321).

#### Scenario: Before launching a worker
- **WHEN** the orchestrator runs `term.sh survey --cwd <dir>`
- **THEN** it sees whether a live session already runs in that folder

#### Scenario: A tab of another tool
- **WHEN** a tab runs a session of a tool other than Claude Code and no registry entry of this home names it
- **THEN** survey reports it as `shell`

### Requirement: HOME-301 Session files
`term.sh` SHALL read a live session's identity from `<dir>/<pid>.json` in the folders matched by `term.sessions_dirs` (comma-separated globs from `.local/config` only, default `${CLAUDE_CONFIG_DIR:-~/.claude}/sessions`), take the profile from the name of the process's `CLAUDE_CONFIG_DIR` when its environment can be read, else from the folder above `sessions` (none for `.claude`), and ignore a file whose `pid` differs from its name or that belongs to a process other than `claude`.

#### Scenario: A file for another program
- **WHEN** a session file exists for the pid of a shell
- **THEN** the shell's tab has no session id

#### Scenario: A shared sessions folder
- **WHEN** a session's file lies under one profile's folder and its process runs with `CLAUDE_CONFIG_DIR` of another profile
- **THEN** its profile is the one of `CLAUDE_CONFIG_DIR`
