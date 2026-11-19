## Why
With one issue per task in the home that owns the work (change one-issue-where-the-work-is), a parent home holds no record of work it handed on, and tasks started straight in a child home were never visible to it. The owner decided that the parent's status reads the open issues, owner questions and live sessions of every related home and shows one combined view; context is read by link, never copied.

## What Changes
- New `scripts/home-status [--all | --home <name>]`: per home, its open issues by state, its owner questions under that home's own owner label, and its open sessions from that home's `.local/registry.json` (live, lost, stopped? or starting; lost only when `term.sh reconcile` marked it). `--all` reads every related home whose role is `child` or `peer`; a parent is read only when named with `--home`.
- A related home is read through its local clone (`homes.<name>.path`): its own `home.config` and `.local/config` give its owner label and its `gh.config_dir`, the way its own scripts read them; no account is switched and no script of the other home runs.
- HOME-015: the `status` skill groups the output of `home-status --all`; a repo that cannot be read is said as such, never as zero.

## Impact
- New `scripts/home-status`, tests (group `status` in `scripts/tests/run.sh`), the `status` skill, the scripts row of the `CLAUDE.md` table, README.
- HOME-019 (the session-start list of child questions) is unchanged.
