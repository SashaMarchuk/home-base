# base-update Specification

## Purpose
The base owns a fixed set of paths that flow down into every home, plus the base block of `CLAUDE.md`. A home takes base changes by a plain git merge from a fetch-only remote, and conflicts are settled by path owner.

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

### Requirement: HOME-050 Update by merge
The `base-update` skill SHALL require a clean working tree, fetch `base`, merge `base/main` without committing, and remove every `base-only` path before settling.

#### Scenario: Dirty tree
- **WHEN** the working tree has uncommitted changes
- **THEN** the update stops and says so

### Requirement: HOME-051 Conflicts settled by path owner
The `base-update` skill SHALL commit and push a clean merge without a question, resolve conflicts that lie only in `flows` paths by taking the base's side after saving the home's dropped diff in one issue labelled `base-sync`, and abort the merge on any other conflict and open one issue with the owner label listing the files and the base commit.

#### Scenario: Conflict in a home-owned path
- **WHEN** the merge conflicts in the buffer of `CLAUDE.md` or a home-owned path
- **THEN** the merge is aborted and one owner issue is opened

#### Scenario: Conflict only in a base-owned script
- **WHEN** the only conflict is in `scripts/`
- **THEN** the base's version is taken and the home's diff is kept in a `base-sync` issue

### Requirement: HOME-127 The dropped diff is written before the issue
Before it opens the `base-sync` issue, the `base-update` skill SHALL write `scratch/base-sync.md` holding the dropped paths, the base commit and the home's diff in a fenced block, and use that file as the issue body.

#### Scenario: Conflict only in flows-down paths
- **WHEN** the base's side is taken for conflicting flows-down paths
- **THEN** `scratch/base-sync.md` with the diff exists before `home-log new --body-file scratch/base-sync.md` runs

### Requirement: HOME-052 After the merge
After a base-update commit the skill SHALL run `scripts/checks/run` and, when `templates/settings.json` changed, report it so the changed hook lines are applied to `.claude/settings.json` keeping `enabledPlugins`.

#### Scenario: Hook template changed
- **WHEN** the merge changed `templates/settings.json`
- **THEN** the report says so and the hook lines are applied by hand

### Requirement: HOME-053 Base ahead and drift are reported
The sweep SHALL add the `base` remote from `base.url` when missing, fetch it with a time limit, and print `SWEEP base-ahead <repo> base/main is <N> commits ahead` with the count of commits `base/main` has that the home lacks and `SWEEP drift <repo> <path>` for each `flows` path the home changed since the merge base.

#### Scenario: Base has new commits
- **WHEN** `base/main` is three commits ahead
- **THEN** the session-start report shows `base/main is 3 commits ahead` and the orchestrator runs the `base-update` skill before the queue

### Requirement: HOME-054 Base-owned paths are fixed in the base
A home SHALL never edit a base-owned path; a fix to one is made in the base.

#### Scenario: Bug in a base script
- **WHEN** a home finds a bug in `scripts/home-log`
- **THEN** the fix is made in the base and reaches the home through a base update
