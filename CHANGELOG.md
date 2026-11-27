# Changelog

Every release of the base, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow [Semantic Versioning](https://semver.org/): a major release asks you to do something by hand and says what under "Do by hand".

Take a release into your home with `scripts/base-update` (see "Take base updates" in the README).

## [1.4.0] - 2026-11-27

### Changed
- Terminal helpers: a "Heads up" notice above a session's input box (the line with "0: Dismiss") is no longer a blocker. `term.sh state` reports the state under it (the word `headsup` is gone), `send`, `park`, `close` and `freeze` type with it shown and never press 0, and `finished` judges the box under it (`unsure:notice` is gone). A text that starts with a digit gets one leading space while a notice shows, so the notice never takes that key (HOME-489).
- `term.sh regroup --dry-run` also plans a tab out of a window it shares with live sessions of another group or place, to a new window (HOME-491).
- `CLAUDE.md` base block: rule 10 says orchestrators never ask the owner to dismiss a notice; new rule 19: the tab's name goes next to each session id or tty named to the owner. The orchestrate and status skills say the same and how an orchestrator gets its name.

### Added
- `term.sh survey --json` gives each tab its `title`: the tab title the owner sees, without the status glyph and " (claude)". For display only, never a target (HOME-490).
- OpenSpec change `notice-and-tab-titles`.

## [1.3.0] - 2026-11-26

### Added
- Terminal helpers: every Claude Code session that `open`, `resume`, `thaw` or `reopen` starts gets a clear name with `--name`: `Orchestrator · <home>` for an orchestrator, `<home> #<issue>` for a worker, or the text of the new `open --name`. Claude Code shows it in the prompt box, the `/resume` picker and the tab title. Adopted tabs keep their own name. Resume lines in issues and freeze snapshots do not change (HOME-487).
- `term.role.<role>.window=<name>` in `.local/config`: every session of that role opens in one window of its own, for example all home orchestrators in an "Orchestrators" window. The tab's group (freeze record, thaw order, selectors) stays as before; `survey --json` shows the `place` (HOME-488).
- OpenSpec change `session-names`.

## [1.2.1] - 2026-11-25

### Fixed
- Wording only, no rule changed: the orchestrate skill and the route skill's description say what routing reads (`home-tree.md`, `home.config` and, when needed, the `## This home` section of a home below); `templates/home.config`, this changelog and the `route-skill` proposal say that with a tree, topics are only hints.
- The 1.2.0 notes leave out one change: without `home-tree.md`, the topics of a `role=parent` or `role=peer` home no longer route a request there. A child asked for its parent's or a peer's work names that home and opens no issue there; the owner may still pick the peer hand-off.

## [1.2.0] - 2026-11-25

### Added
- `route` skill: decides for each new request whether it stays in this home or goes to a home below it, from `home-tree.md`. One fit below: the issue goes there. Two fits: one question with the fitting homes. Routing goes down only; a request for a home above or beside gets no issue there (HOME-485).
- `templates/home-tree.md`: the tree of homes, each named by its repo, with Domain, Belongs and Not here (HOME-486). `home-tree.md` is the home's own file.
- OpenSpec change `route-skill`: the design and the evaluation (16 cases).

### Changed
- Orchestrate section 7 step 0 and task step 3 call the `route` skill. `homes.<name>.topics` decide only when a home has no `home-tree.md`; with a tree they are only hints.
- `CLAUDE.md` base block: every new request goes through `route` first; `home-tree.md` in "Where things live".

## [1.1.0] - 2026-11-24

### Added
- `CLAUDE.md` base block, rule 13: a session is resumed only under the account (profile) it was first launched under, never under another.
- OpenSpec change `sticky-session-account` (proposed, not built yet): HOME-484, the terminal helpers keep the first profile recorded for a session and report a session that runs under another one.

## [1.0.1] - 2026-11-22

### Fixed
- `scripts/base-update`: the home is always the folder above the script's `scripts/` folder. The base's own copy, or a test run from inside a home, no longer updates that home.
- A release may turn a base file into a folder, or a base folder into a file.
- Release tags are fetched with `--no-tags`, so they never land among a home's own tags (the sweep's plain fetch did that).

### Changed
- README and `base.manifest`: an update never deletes a home's own file at a base-only path; `scripts/checks/run` reports it, because a home keeps those names free.

## [1.0.0] - 2026-11-22

The first release. Homes made before it have no `VERSION` file; their first `scripts/base-update` finds the base commit they last merged and starts from there.

### Added
- Releases: tags `vX.Y.Z`, this changelog and a GitHub release for each. `main` moves only at a release.
- `VERSION`: the base release a home is on.
- `scripts/base-update`: one command for people and agents. Update to the newest release, to `base.pin`, or to a chosen version; `--dry-run` changes nothing; `--rollback` goes back one release with a new commit; `--check` prints the current, newest and target release. It refuses uncommitted changes and stops with exit 3 when the base cannot be reached.
- Base-owned paths always take the release's exact content. A home's edits to them are saved as a patch in `.local/base-update/` and listed, with where that text belongs; files a home added inside a base folder stay.
- README: "Your own rules and settings", the places a base update never touches.

### Changed
- The `base-update` skill runs `scripts/base-update` instead of its own git steps.
- The sweep reports `base-ahead` when a newer release (or the newest within `base.pin`) is out, and `drift` against the release the home is on.
- `CLAUDE.md` base block: rule 16 names the home section as the place for your own rules (a rule there may replace a base rule it names); "Where things live" lists your own places and `VERSION`.
