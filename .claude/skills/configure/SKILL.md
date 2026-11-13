---
name: configure
description: Make this repo the user's own home from the base. Use when someone says "configure", "set up my home", "make a home from this base", "onboard me", after cloning the base, or with an answers file ("configure --answers <file>") for an unattended setup.
---

# configure

One code path: `scripts/configure --answers <file> [--labels]`. Interactive mode only collects the answers. `templates/answers.example` lists every key with an example.

## With an answers file
Run `scripts/configure --answers <file> --labels`. Exit 2 lists every missing or invalid key: ask for exactly those (or report them when unattended) and run again. Exit 3: the repo is not ready (no `CLAUDE.md` with the base block and buffer, or a template missing): take them from the base first. Exit 4: the files are written but the labels could not be created, because the GitHub repo does not exist yet or this account cannot reach it: create it (private), push, then run `scripts/labels`.

## Interactive (grill)
Use the surface's ask tool, at most four questions per round, recommended option first. Skip anything already in `.local/answers` from an earlier run.
1. Who and what: `owner.names`, `home.domain` (one line), `home.boundary` (what must never enter), `home.rules` (the owner's own rules a cloud or other-agent session would need; zero or more).
2. Repo and languages: `repo` (`owner/name`), `lang.files`, `lang.owner`, `base.url` (where the base lives; suggest the current `origin` of the clone if it is the base).
3. Tracker: `tracker.board` (`none` or `clickup`), `tracker.board_write` (`ask-first`, `yes`, `read-only`), `labels.needs_owner` (default `needs-owner`).
4. Related homes: for each, `homes.<name>.repo`, `.path`, `.role` (`parent`, `child`, `peer`).
5. Behaviour: `limits.mode` (`none` default; `soft`, `hard`), `limits.threshold`, `proactivity.mode` (`assigned` default; `off`, `watch`), `dreams.mode` (`manual` default; `daily`), `facts.sink` (`none` or an MCP server name), `guard.extra` (extra blocked command patterns).
6. Plugins: which plugins this home enables (`plugins`, comma list of `name@marketplace`; empty is fine). Core paths never need a plugin.
7. Accounts: more than one CLI profile or workspace account? (`accounts.multi`). On yes, one row each: `label | what it serves | where the mapping lives`. Labels only; never write an address.
8. This machine: `gh.config_dir`, `launch.profile.orchestrator`, `launch.profile.worker`, `launch.model` (an alias), `launch.command`, `launch.profile_flag`, `transcripts.paths`, `transcripts.exclude`, `limits.reader`, `guard.private_values`.
9. Terminal helpers (`terminal_helpers`): offer `on` only on macOS with iTerm2; the script runs the device check and keeps `off` if it fails.

Write every answer as `key=value` lines to `.local/answers` (gitignored; repeatable keys one line each), then run `scripts/configure --answers .local/answers --labels`.

## Finish
1. Completeness check: compare the script's "keys used" list with the questions above; every key must show `(answer)` or a default the user accepted. Ask for any gap and rerun (it is idempotent).
2. Remind the user: accept the trust prompt once when opening the home; commit the written files.
