# checks Specification

## Purpose
The same repo checks run before every commit and in CI, and hooks guard a running session: they block risky shell commands and personal values written into tracked files. One pattern definition serves the guard, the checks and the record tool.

## Requirements

### Requirement: HOME-065 Checks on staged content and in CI
`scripts/checks/run` SHALL check, with `--staged` from the git pre-commit hook, only the staged paths as they are in the git index (content, symlink mode and target), and all tracked files of the working tree otherwise, failing with exit 1 and one `checks: FAIL` line per problem.

#### Scenario: Pre-commit
- **WHEN** a commit is made with `core.hooksPath=.githooks`
- **THEN** the checks run on the staged content and a failure stops the commit

#### Scenario: Working tree differs from the index
- **WHEN** a file is staged clean and then edited in the working tree to hold a personal value
- **THEN** `--staged` checks the staged version and passes

#### Scenario: CI outside a home
- **WHEN** the `home-checks` workflow runs in a repo without `home.config`
- **THEN** it skips the checks

### Requirement: HOME-066 Secrets and personal values
The checks SHALL fail on a secret found by a secret scanner when one is installed and on every hit of the personal-value patterns: tokens, card numbers passing the Luhn check, IBANs passing mod 97, phone numbers, document numbers, the private literals of `guard.private_values` and the terms of `guard.boundary_terms`.

#### Scenario: Link with an id
- **WHEN** a file holds a URL whose path contains a long number
- **THEN** the URL is removed before the value patterns run and it passes

#### Scenario: Card number
- **WHEN** a tracked file holds a card number that passes the Luhn check
- **THEN** the checks fail and the hit is printed masked

### Requirement: HOME-067 Size and shape of the repo
The checks SHALL fail on any file larger than 500 KB, a `CLAUDE.md` larger than 16 KiB or missing the base markers and the four exact buffer lines after `BASE:END`, the Codex instruction file or skills folder not being relative symlinks to `CLAUDE.md` and `../.claude/skills`, duplicate ids in `DECISIONS.md`, and a `base-only` path tracked in a home.

#### Scenario: Buffer line edited
- **WHEN** a buffer line in `CLAUDE.md` is changed
- **THEN** the checks fail

#### Scenario: Requirements folder in a home
- **WHEN** a home tracks a file under `openspec/`
- **THEN** the checks fail with `base-only path present in a home`

### Requirement: HOME-174 Plugin drift between Claude Code and Codex is reported
When a home has `.codex/config.toml` and `.claude/settings.json`, the checks SHALL print one `checks: drift:` line for each plugin enabled for one tool only, and SHALL NOT fail on it.

#### Scenario: Plugin enabled for Codex only
- **WHEN** `.codex/config.toml` enables a plugin that `.claude/settings.json` does not
- **THEN** the checks print a drift line naming it and still pass

#### Scenario: No Codex settings
- **WHEN** a home has no `.codex/config.toml`
- **THEN** no drift line is printed

### Requirement: HOME-068 Bash guard
The pre-tool hook for shell commands SHALL block with exit 2 and a reason any command that kills by pattern or more than one process (only one optional signal and single positive process ids above 1 pass), switches the CLI account, force-pushes the default branch, deletes a repository, changes its visibility, pushes to the base remote, or matches a regex in `guard.extra`.

#### Scenario: Kill by pattern
- **WHEN** a session runs `kill $(pgrep node)`
- **THEN** the command is blocked

#### Scenario: Kill by pattern inside another command
- **WHEN** a session runs `bash -c "pkill node"` or `/usr/bin/killall Dock`
- **THEN** the command is blocked

#### Scenario: Signal by name to an exact id
- **WHEN** a session runs `kill -s TERM 1234`
- **THEN** the command is allowed

#### Scenario: Account switch
- **WHEN** a session runs `gh auth switch`
- **THEN** the command is blocked and the reason names the configured account rule

#### Scenario: A kill of every process or of a group
- **WHEN** a session runs `kill -9 -1`, `kill 0`, `/bin/kill -9 -1` or `for p in $list; do kill $p; done`
- **THEN** the hook blocks it with exit 2

### Requirement: HOME-069 Sensitive-value guard
The pre-tool hook for file writes and edits SHALL block with exit 2 any write of a personal value into a file inside the repo that git does not ignore, new files included, and leave ignored paths and files outside the repo unchecked.

#### Scenario: Value into the wiki
- **WHEN** a session writes an IBAN into a wiki page
- **THEN** the write is blocked and the session is told to keep a link or use `.local/`

#### Scenario: Value into a machine file
- **WHEN** a session writes the same value under `.local/`
- **THEN** the write is allowed

### Requirement: HOME-070 Session-start report
The session-start hook SHALL print a short report of open owner questions, sweep findings, the limits mode and verdict and a due Dreams run, set `core.hooksPath=.githooks` whenever it holds another value, and always exit 0.

#### Scenario: Slow network
- **WHEN** the sweep does not finish within 40 seconds
- **THEN** it is stopped, the report says `sweep: timed out` and the session starts

#### Scenario: Outside a home
- **WHEN** the repo has no `home.config`
- **THEN** the hook prints nothing

### Requirement: HOME-124 Issue first, at session start
The session-start hook SHALL print the line "Every request gets an issue first: first call scripts/home-log new --title T --body B --start (opens and claims it); last scripts/home-log finish <n> --text ..., a question or an explanation included.", and the `orchestrate` and `task` skills SHALL open with that step.

#### Scenario: A short ask
- **WHEN** the owner asks for an explanation in a new session
- **THEN** the session has seen the issue-first line and opens an issue before it answers

### Requirement: HOME-073 Checks of the base itself
The base's own CI workflow SHALL fail when a secret is found in the tree or the history, a tracked file holds a home-directory path or an email address other than a noreply address, a tracked path is not covered by `base.manifest`, `scripts/checks/run` fails, or the script tests fail, and it confirms that the home checks stay silent without `home.config`.

#### Scenario: Path missing from the manifest
- **WHEN** the base tracks a file that no line of `base.manifest` covers
- **THEN** the workflow fails and names the file

#### Scenario: Personal email address
- **WHEN** a tracked file holds an email address that is not a noreply address
- **THEN** the workflow fails
