## Why
HELD: waits for the owner's yes. Do not apply or archive this change until the owner approves it.

The approved freeze keeps a tab with an unsent draft open and never interrupts a running turn (HOME-059 kept), and writes files only under the `.local/` of the home that runs it (HOME-062 kept). The design proposes two opt-in exceptions and a wider file rule; each changes what the owner already approved, so each needs his explicit yes.

## What Changes
- `term.freeze.drafts=save`: a hard freeze saves a real draft locally, clears exactly it and closes the tab; thaw types it back without Enter. Needs a raw box reader that passes the real-tab check first.
- `term.freeze.busy=interrupt`: a hard freeze presses Esc once on a turn still running after the grace time, saves the last screen lines and closes the tab; thaw asks the session to check the interrupted step before repeating it.
- HOME-062 wider: `term.sh` may write files under the `.local/` of a home named in `homes.*` (so a group's files stay with the home that owns the group), not only this home's.
- `scripts/configure --set` then accepts `save` and `interrupt`.

## Impact
- `scripts/term/freeze.sh`, `scripts/term/thaw.sh`, a raw box reader in `scripts/term/term.sh`, `scripts/configure`, tests.
- Until approved, the code keeps `skip` and `wait` and writes only under this home's `.local/`.
