## MODIFIED Requirements

### Requirement: HOME-302 Where a session id comes from
`term.sh` SHALL take a tab's session id from this home's registry only while the entry's pid is the live process and the session file names no other id, else from its session file, else its command line; when the entry's pid, tty and tab id still match the live tab and that process's session file names another id (as after `/clear`), the tab keeps its registration and issue, its id and resume line come from the session file, and freeze and park SHALL update the entry to that id before any key, keeping the first id as the id of the run on the issue; freeze keeps a tab whose registry entry names another process as `kept:changed`, and a tab with no id SHALL get no resume line.

#### Scenario: No session file and no id
- **WHEN** a tab runs `claude -r` and no session file exists for its process
- **THEN** `survey --json` gives it no session id and no resume line

#### Scenario: A new session in a reused tab
- **WHEN** the session this home opened in a tab exited and a new `claude` session runs in the same tab
- **THEN** freeze sends that tab no key and lists it as `kept:changed`

#### Scenario: The session was cleared in its own tab
- **WHEN** the owner ran `/clear` in a worker tab, so the same process on the same tty and tab now has a session file with a new id, and `freeze --hard` runs on it
- **THEN** the registry entry names the new id and a resume line for it, the freeze record lists that id, and the tab is closed

#### Scenario: The entry cannot be updated
- **WHEN** the registry cannot be written for a session that moved to a new id
- **THEN** the tab receives no key and is listed as `kept:no-record`

### Requirement: HOME-311 Hard close per state
`freeze --hard` SHALL type `/exit` into an idle, empty box and check the process is gone, treat a box whose text one ghost probe shows to be a suggestion or a placeholder hint as empty and type `/exit` straight after that probe, keep a tab with a real draft, press Esc once on a dialog already recorded (never an option; kept if it stays open), keep a running turn after `term.freeze.hard_grace` seconds without any key, and report a process that outlives `/exit` with exit 5, never signalling it.

#### Scenario: Running turn
- **WHEN** a tab's turn is still running after the grace time
- **THEN** no Esc or other key is sent and the tab is listed as `kept:busy`

#### Scenario: Unsent draft
- **WHEN** the box holds text the owner typed
- **THEN** only the probe character and its backspace are typed, the text stays, and the tab is listed as `kept:draft`

#### Scenario: Placeholder hint in an empty box
- **WHEN** a fresh session's empty box shows a hint that comes back whenever the box is empty
- **THEN** one probe is typed and taken back, `/exit` follows, and the tab is closed

### Requirement: HOME-314 Soft close prompt
`freeze --soft` SHALL type one prompt per tab only while both signals say idle and the box is empty or holds only what one ghost probe shows to be a suggestion or a placeholder hint, never interrupting a turn or touching a dialog, asking the session to pause and write `.local/freeze/<id>/<session id>.md` ending with the line `nonce: <N>`, `N` random per tab.

#### Scenario: Busy tab
- **WHEN** a tab's turn runs for the whole soft timeout
- **THEN** no key is sent and the tab is listed as `kept:soft-timeout`

#### Scenario: Placeholder hint in an empty box
- **WHEN** an idle session's empty box shows a placeholder hint
- **THEN** the prompt is typed straight after one probe

## ADDED Requirements

### Requirement: HOME-413 The identity is read again before the exit
Right before `freeze` types `/exit` into a tab, it SHALL read that process's session file again and, when the file names a session id other than the recorded one, send no further key and list the tab as `kept:changed`.

#### Scenario: The session moved after the snapshot
- **WHEN** the session file of a tab names a new id between the freeze snapshot and the exit
- **THEN** `/exit` is not typed and the tab is listed as `kept:changed`
