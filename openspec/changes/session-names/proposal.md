## Why
An owner who runs many sessions in the same repos cannot tell a home's orchestrator from the other sessions open there: every tab shows an automatic name. Several homes (a parent and its children) each have an orchestrator, and the owner wants to find each one at a glance and keep all of them in one window, apart from the workers.

Facts used (checked on a real machine, Claude Code 2.1):
- `claude --name <name>` sets the session's display name: the prompt box, the `/resume` picker and the terminal title. It works with `--session-id <id>` (a new session) and with `--resume <id>` (it renames the session), and the name is kept in the transcript.
- iTerm2 shows that terminal title as the tab title ("<name> (claude)").
- `/rename [name]` renames a running session from its input box.

## What Changes
- New HOME-487: `open`, `resume`, `thaw` and `reopen` start a Claude Code session with `--name <name>`, right after its session id. The name: the registry entry's `name` (new `open --name TEXT`), else "Orchestrator · <home>" for an orchestrator (the repo name in the folder's `home.config`, else the folder's name), else "<this home> #<issue>" for a worker with an issue, else "<this home> · <folder>". An adopted tab and a session of another role (the owner's own) get no name. The recorded resume line stays without it, so issues and freeze snapshots do not change. A tab is still never addressed by its title.
- New HOME-488: `term.role.<role>.window=<name>` (`.local/config` only) places every session of that role in one window of its own, found as a group's window is found (the window holding most live tabs of that place, else the cached one, else a new window). The tab's group does not change: the freeze record, thaw order and the `--group` selectors still follow it. `survey --json` gives each tab a `place` (that name, else its group); `regroup --dry-run` plans by place.

## Impact
- `scripts/term/term.sh` (`launch_tab`, `open`, `resume`), `scripts/term/sessions.sh` (names, `role_window`, `window_for_group`, survey), `scripts/term/thaw.sh`, `scripts/term/recover.sh`; tests on the fake backend (must-pass and must-fail).
- `templates/home.config` lists the new machine key; the orchestrate skill names `--name` and the key.
- No new dependency. Without the key, placement is as before.
