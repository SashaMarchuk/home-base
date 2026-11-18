## MODIFIED Requirements

### Requirement: HOME-055 Off unless switched on
Every verb of `scripts/term/term.sh` SHALL exit 3 without opening or typing anything unless `terminal_helpers=on` is set, and `open`, `freeze` and `thaw` SHALL also exit 3 when they run in a Codex session (`CODEX_THREAD_ID` set) or with `launch.command=codex`, because they launch or reopen Claude Code tabs only.

#### Scenario: Helpers off
- **WHEN** `term.sh open` runs with `terminal_helpers=off`
- **THEN** it exits 3 and no tab is opened

#### Scenario: Codex orchestrator
- **WHEN** `term.sh open` runs with `terminal_helpers=on` from a Codex session or with `launch.command=codex`
- **THEN** it exits 3 and no tab is opened

#### Scenario: Codex orchestrator reads the tabs
- **WHEN** `term.sh survey` runs with `terminal_helpers=on` from a Codex session
- **THEN** it lists the live tabs as from any other session

### Requirement: HOME-321 Survey in JSON
`term.sh survey --json` SHALL print one JSON object per live tab with its tty, window, tab id, pid, kind (`claude`, `codex` or `shell`), session id and its source, profile, session-file status, cwd, group and its source, registration, issue, resume line and whether it is the calling session.

#### Scenario: A Codex tab
- **WHEN** a `codex` process runs on a tab and HOME-327 finds no thread id for it
- **THEN** its kind is `codex` and it has no session id or resume line

#### Scenario: A mapped Codex tab
- **WHEN** a `codex` process runs on a tab and HOME-327 finds its thread id
- **THEN** its kind is `codex`, its session id is that thread id with the source `codex-record`, and its resume line is `cd <cwd> && codex resume <id>`

## ADDED Requirements

### Requirement: HOME-326 The Codex thread record
On the Codex surface, the SessionStart hook SHALL write `.local/codex-threads/<tty name>` (mode 600) holding the thread id from the `session_id` of the hook's JSON input, the pid of the nearest `codex` process above the hook on that tty, the cwd and the time, and SHALL write nothing when the id is not a UUID, the hook has no tty or no `codex` process is above it.

#### Scenario: A Codex session starts in a tab
- **WHEN** Codex starts on `ttys004` in a home and runs its SessionStart hook with that thread's `session_id` in the hook's input
- **THEN** `.local/codex-threads/ttys004` holds that id, the pid of the `codex` process on `ttys004`, the cwd and the time

#### Scenario: No tty
- **WHEN** the hook runs without a controlling tty
- **THEN** no record is written

### Requirement: HOME-327 The thread id of a Codex tab
`term.sh` SHALL give a Codex tab a thread id only when the record for its tty names the pid of the live `codex` process on that tab, the id's rollout file exists under the Codex sessions folder, and no `cli` thread for the same cwd was created after the record's time; in every other case the tab has no thread id, gets no resume line and is listed only.

#### Scenario: The pid changed
- **WHEN** the record for a tab's tty names a pid that no longer runs on that tab
- **THEN** the tab has no thread id and nothing is typed into it

#### Scenario: A new thread inside the session
- **WHEN** a `cli` thread for the tab's cwd was created after the record's time (for example after `/new`)
- **THEN** the tab has no thread id and nothing is typed into it

### Requirement: HOME-328 Park and resume of a Codex tab
`term.sh park` and `term.sh resume` SHALL act on a Codex tab only when HOME-327 gives it a thread id, under the same draft, busy-turn and record rules as a Claude Code tab, writing `cd <cwd> && codex resume <id>` as its resume line, and `resume` SHALL reopen it with that line.

#### Scenario: Park a mapped Codex worker
- **WHEN** `term.sh park <tty> --adopt --issue 5` runs on an idle mapped Codex tab with an empty box
- **THEN** issue 5 holds `cd <cwd> && codex resume <id>` and the session is ended with its exit command

#### Scenario: Park an unmapped Codex tab
- **WHEN** `term.sh park <tty> --adopt --issue 5` runs on a Codex tab without a thread id
- **THEN** it exits 3 and nothing is typed

### Requirement: HOME-329 Codex tabs pass a real-tab check first
Before any Codex tab of the owner is parked or closed, a check on throwaway tabs that the check itself opens (outside `term.sh open`, which stays Claude-only) SHALL pass: a Codex session started in a sandbox home gets its record, `survey` shows its id, `park` ends it, `resume` brings back the same thread id, and after `/new` the tab has no thread id; until then `park` and `close` act only on Codex tabs the session opened itself.

#### Scenario: The check has not passed
- **WHEN** the orchestrator is asked to park a Codex tab of the owner before the check passed
- **THEN** it lists the tab and parks nothing
