## Why
The bash guard lets `kill <any literal PID>` through, so a session can end a process it never started: another session, another tool, or a PID the system reused. An exact number is not proof of ownership.

## What Changes
- HOME-068: a kill of exact process ids no longer passes on its form alone; it passes only under HOME-350 or after the confirmation of HOME-351. Everything blocked before stays blocked. A kill inside `sh -c "..."` and a kill after a single `&` are now read like any other kill.
- HOME-350 (new): a kill passes silently only when every target is a descendant of the calling agent session or a live entry of this home's registry.
- HOME-351 (new): any other exact id makes Claude Code ask the user to confirm, naming the id and its command; Codex refuses and tells the agent to ask the owner to run the kill.
- HOME-352 (new): the guard refuses when ownership cannot be determined.
- HOME-354 (new): a command that holds the word `kill` where the guard cannot read it as a kill of exact ids (behind `timeout`, `nice`, a trap, a case arm, a function body) is asked in Claude Code and refused on Codex; text stays allowed after a fixed list of commands and where a plain word follows. HOME-068 also reads a kill behind a path before the shell name, `--` after `-c`, `VAR=value`, quotes, a backslash, a leading redirection, `if`/`while`/`until` and several `&`.
- HOME-353 (new): signal 0 (a liveness probe) stays allowed for any exact id.

Measured before the build, Claude Code 2.1.327, `claude -p` in a throwaway folder, a hook that answers `ask` for a kill of a `sleep` the test spawned: in `default` mode (with the tool allowed) and in `bypassPermissions` mode the call did not run and was listed as a permission denial; with a hook that answers nothing the same call ran in both modes. The hook input carried `permission_mode` in every run. So `ask` holds under bypass in a run with no one to answer; no config key is added. Not observed: the prompt itself in an interactive bypass session.

## Impact
- `scripts/hooks/bash-guard`, `scripts/hooks/codex-pre-tool`, `scripts/tests/run.sh`.
- A background process whose parent shell already exited (started with `&` in an earlier call) is no longer a descendant of the session, so its kill asks.
