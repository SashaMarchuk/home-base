# base-update Specification

## Purpose
The base owns a fixed set of paths that flow down into every home, plus the base block of `CLAUDE.md`. The base ships SemVer releases; a home moves between them with one command that sets the base-owned paths to a release's exact content and keeps the home's own edits safe.

## Requirements

### Requirement: HOME-048 The manifest names every base path
`base.manifest` SHALL cover every path tracked in the base with one line `<kind> <path>`, where the kind is `shared` (the base block and buffer flow down, the home section below is the home's), `flows` (owned by the base, present and never edited in a home) or `base-only` (present in the base repo only).

#### Scenario: Requirements stay in the base
- **WHEN** a home takes a base update
- **THEN** the `openspec/` folder, listed `base-only`, is not present in the home

### Requirement: HOME-049 The base remote is fetch-only
A home's `base` remote SHALL have its push URL set to `DISABLED`, and the bash guard blocks any `git push base`.

#### Scenario: Push attempt
- **WHEN** a session runs `git push base main`
- **THEN** the guard blocks it with exit 2

### Requirement: HOME-050 Update by command
`scripts/base-update` SHALL be the one way a home takes the base: people run it by hand and the `base-update` skill runs the same command. It SHALL refuse, changing nothing, when tracked files have uncommitted changes, when a merge, rebase, cherry-pick or revert is in progress, or when `CLAUDE.md` lacks exactly one `BASE:BEGIN`, one `BASE:END` and one `BUFFER 4/4` line in that order. It SHALL fetch the base's release tags into `refs/base-tags/` with `--no-tags`, never into the home's own tags, run from a temporary copy of itself, make one commit and never push.

#### Scenario: Dirty tree
- **WHEN** a tracked file has uncommitted changes
- **THEN** the command exits 1, says to commit or stash, and nothing changes

#### Scenario: An untracked file
- **WHEN** only untracked files exist and none sits where the release puts a file
- **THEN** the update runs and the untracked files stay

### Requirement: HOME-051 Base-owned paths take the release
An update SHALL record the release in history as a merge with the strategy `ours` and then set every path of the release's `base.manifest` to the release's exact content: the `flows` paths (files the release no longer has, and the old release had, are removed; files the home added inside a `flows` folder stay and are listed), and the base block and buffer of `CLAUDE.md` with the home section below them kept as it is. `base-only` paths SHALL never enter a home, and an update SHALL never delete a home's own file at a `base-only` path (`scripts/checks/run` reports it). It SHALL never touch a path the manifest does not list.

#### Scenario: Conflict-free by construction
- **WHEN** the home and the release both changed `scripts/home-log`
- **THEN** the home gets the release's `scripts/home-log` and the home's edit is saved as in HOME-127

#### Scenario: The home section
- **WHEN** the release changes the base block of `CLAUDE.md`
- **THEN** the base block equals the release's and every line after `BUFFER 4/4` is unchanged

### Requirement: HOME-127 The home's edits are saved before they are replaced
Before it replaces a base-owned file whose content differs from both the release the home is on and the target release, `scripts/base-update` SHALL save the home's edits as a patch against the release the home is on in `.local/base-update/<from>-to-<to>-<UTC time>.patch`, list the files and say where such text belongs (rules in the home section of `CLAUDE.md`, settings in `home.config` or `.local/config`, scripts in `tools/`, skills in `.claude/skills/<own name>/`). The `base-update` skill SHALL then write `scratch/base-sync.md` holding the files, the release and the patch in a fenced block, and open one `base-sync` issue with it as the body.

#### Scenario: An edited base script
- **WHEN** the home edited `scripts/tool` and updates
- **THEN** the patch holds the edit, applies to the old release's file, and `scripts/tool` equals the release's

#### Scenario: Unchanged base files
- **WHEN** a base file differs from the old release only because the release changed it
- **THEN** it is not in the patch

### Requirement: HOME-052 After the merge
After a base-update commit the skill SHALL run `scripts/checks/run` and, when `templates/settings.json` changed, report it so the changed hook lines are applied to `.claude/settings.json` keeping `enabledPlugins`.

#### Scenario: Hook template changed
- **WHEN** the merge changed `templates/settings.json`
- **THEN** the report says so and the hook lines are applied by hand

### Requirement: HOME-053 A newer release and drift are reported
The sweep SHALL add the `base` remote from `base.url` when missing, fetch it and its release tags with a time limit, and print `SWEEP base-ahead <repo> base release <vX.Y.Z> is out (this home is on <vA.B.C|none>)` when the target release (`base.pin` or the newest) is newer than `VERSION`, and `SWEEP drift <repo> <path>` for each `flows` path that differs from the base content the home is on. Before the base has any release it SHALL compare with `base/main` as before (`base/main is <N> commits ahead`).

#### Scenario: A newer release
- **WHEN** the home is on v1.1.0 and v1.3.0 is out
- **THEN** the session-start report shows `base release v1.3.0 is out (this home is on v1.1.0)` and the orchestrator runs the `base-update` skill before the queue

#### Scenario: Pinned and current
- **WHEN** `base.pin=1.1` and the home is on the newest v1.1.x
- **THEN** no `base-ahead` line is printed

### Requirement: HOME-054 Base-owned paths are fixed in the base
A home SHALL never edit a base-owned path; a fix to one is made in the base.

#### Scenario: Bug in a base script
- **WHEN** a home finds a bug in `scripts/home-log`
- **THEN** the fix is made in the base and reaches the home through a base update

### Requirement: HOME-476 Releases
The base SHALL publish releases as annotated SemVer tags `vX.Y.Z`, each with a section `## [X.Y.Z] - <date>` in `CHANGELOG.md` (Keep a Changelog; a major release lists what to do by hand) and a GitHub release whose notes are that section. `main` SHALL move only at a release, so its newest commit is always a tagged release.

#### Scenario: A release
- **WHEN** the maintainer publishes `main`
- **THEN** its commit carries the tag `v$(cat VERSION)` and `CHANGELOG.md` has that version's section

### Requirement: HOME-477 VERSION names the release
The base SHALL ship `VERSION`, a `flows` file holding the release number `X.Y.Z`. `scripts/base-update` SHALL treat the release it names as the base content the home is on, and refuse when no tag of that release exists.

#### Scenario: After an update
- **WHEN** a home updates to v1.3.0
- **THEN** its `VERSION` holds `1.3.0`

### Requirement: HOME-478 The target release
`scripts/base-update` SHALL update to the version given (`1.4.0` or `v1.4.0`), else to the newest release matching `base.pin` (`1.4` is the newest `1.4.x`, `1.4.2` exactly that one), else to the newest release. An older version given by name SHALL be applied the same way, with no merge. It SHALL refuse an unknown release (exit 1) and a malformed version (exit 2). `--check` SHALL print the lines `current`, `newest`, `target`, `update` (a release to take, or `none`) and `base` (the base commit the home is on) and change nothing.

#### Scenario: Skipped releases
- **WHEN** a home on v1.0.0 updates while v1.3.0 is the newest
- **THEN** it lands on v1.3.0 in one commit and prints the changelog sections of v1.1.0 to v1.3.0

#### Scenario: An older release by name
- **WHEN** a home on v1.1.0 runs `scripts/base-update 1.0.0`
- **THEN** its base-owned paths equal v1.0.0's in one new commit

#### Scenario: Pinned
- **WHEN** `base.pin=1.1` and v1.3.0 is the newest
- **THEN** the update lands on the newest v1.1.x

### Requirement: HOME-479 Dry run
`scripts/base-update --dry-run` SHALL run the same update in a temporary worktree, print the files that would change, the edits that would be saved and the changelog sections, and remove the worktree, leaving the home's commits, files and worktrees as they were; like `--check`, it only fetches the release tags.

#### Scenario: Nothing changes
- **WHEN** the dry run finishes
- **THEN** HEAD, `git status` and the worktree list are as before

### Requirement: HOME-480 Rollback
`scripts/base-update --rollback` SHALL make one new commit that sets the base-owned paths to the content of the release named before the last recorded update (`Base-Update: <from> -> <current>` trailer), saving the home's edits as in HOME-127; it SHALL never reset or revert, and SHALL refuse when the last recorded base change is not an update to the current release or when the home was on no release before it. A later update SHALL give the same base content as a direct update.

#### Scenario: Update, roll back, update
- **WHEN** a home updates from v1.1.0 to v1.3.0, rolls back, and updates again
- **THEN** its base-owned paths equal v1.3.0's and no edit is saved

### Requirement: HOME-481 The base cannot be reached
When fetching the base fails, `scripts/base-update` SHALL exit 3 and say nothing changed; a rollback SHALL need no fetch.

#### Scenario: Offline
- **WHEN** the base remote cannot be reached
- **THEN** an update exits 3 with the home unchanged, and `--rollback` still works

### Requirement: HOME-482 First update of a home made before releases
For a home without `VERSION`, `scripts/base-update` SHALL take the merge base of the home and the target release as the base content the home is on, name it by its release tag or `unreleased-<short commit>`, and refuse when the home shares no history with the base.

#### Scenario: An old home
- **WHEN** a home that merged an untagged base commit updates to v1.0.0
- **THEN** the update starts from that commit and saves no edit the home did not make

### Requirement: HOME-483 The home's own places
The base SHALL document the places a base update never touches: the home section of `CLAUDE.md` (a rule there may replace a base rule it names), `home.config`, `.local/config`, `tools/`, `.claude/skills/<a name the base does not use>/`, `wiki/` and `DECISIONS.md`.

#### Scenario: A customized home updates
- **WHEN** a home with its own config, tools, skill, wiki and home section updates
- **THEN** none of those files changes
