## MODIFIED Requirements

### Requirement: HOME-062 No force-close
`term.sh` SHALL end a session only by typing its exit command, never signal a session's process, and write files only under the `.local/` of this home or of a home named in `homes.*`.

#### Scenario: Lingering session
- **WHEN** a session's process does not exit after `/exit`
- **THEN** close exits 5, no process is signalled and the tab is left as it is

#### Scenario: A group owned by a related home
- **WHEN** a freeze includes a tab whose group's home is a related home
- **THEN** that tab's snapshot and checkpoint files are written under that home's `.local/freeze/`, and no file is written outside a home's `.local/`

### Requirement: HOME-312 Conservative freeze values and continuing
`term.sh freeze` SHALL apply `term.freeze.drafts=save` and `term.freeze.busy=interrupt` only as HOME-324 and HOME-325 describe, treat any other value as `skip` and `wait`, and `freeze --continue <id>` SHALL act again on the tabs kept for a running turn, disagreeing signals, a draft or a soft timeout.

#### Scenario: A hand-written opt-in
- **WHEN** `.local/config` holds an unknown value such as `term.freeze.busy=maybe` and a tab's turn is running
- **THEN** freeze sends it no key

## ADDED Requirements

### Requirement: HOME-324 Saving a draft at a hard freeze
Only under `freeze --hard` with `term.freeze.drafts=save`, and only after the snapshot and the record, `term.sh` SHALL save a real draft read by a raw box reader to `.local/freeze/<id>/<session id>.draft` (mode 600), read it back, delete exactly its characters, check the box is empty and then close the tab, keeping the tab untouched on any mismatch; the draft never enters an issue, and thaw types it back without Enter.

#### Scenario: Draft with spaces, two lines and multi-byte characters
- **WHEN** the box holds such a draft and the freeze saves it
- **THEN** the saved text equals the box byte for byte, and after thaw the same text is in the reopened box with nothing sent

#### Scenario: Read-back mismatch
- **WHEN** the saved file differs from the box
- **THEN** nothing is deleted and the tab is listed as `kept:draft`

### Requirement: HOME-325 Interrupting a running turn at a hard freeze
Only under `freeze --hard` with `term.freeze.busy=interrupt`, and only after the snapshot and the record, `term.sh` SHALL wait `term.freeze.hard_grace` seconds for a running turn, then press Esc once, wait for the tab to be idle, save its last 20 screen lines as `interrupted` and close it; thaw then asks the session to check what the interrupted step already did before repeating it.

#### Scenario: Turn ends within the grace time
- **WHEN** the turn ends before the grace time
- **THEN** no Esc is pressed

#### Scenario: Turn still running
- **WHEN** the turn still runs after the grace time
- **THEN** exactly one Esc is pressed
