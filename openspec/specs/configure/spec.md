# configure Specification

## Purpose
A clone of the base becomes the owner's own home through one code path: `scripts/configure --answers <file>`. The interactive skill only collects the answers. Settings live in two flat key=value files, one committed and one per machine.

## Requirements

### Requirement: HOME-034 One code path for setup
The `configure` skill SHALL collect answers and defaults interactively into `.local/answers` and then run `scripts/configure --answers .local/answers --labels`, the same command an unattended setup runs with its own answers file.

#### Scenario: Unattended setup
- **WHEN** a filled answers file is passed to `scripts/configure --answers`
- **THEN** the home is configured with no questions asked

### Requirement: HOME-035 All problems reported, nothing written
`scripts/configure` SHALL list every missing required key and every invalid value and exit 2 with nothing written when any exists.

#### Scenario: Missing and invalid answers
- **WHEN** the answers lack `lang.owner` and hold `limits.mode=sometimes`
- **THEN** both are reported, the script exits 2 and no file changes

#### Scenario: Repo is the base itself
- **WHEN** `repo` names the same repository as `base.url`
- **THEN** it is reported as invalid, the script exits 2 and no file changes

#### Scenario: Unknown key
- **WHEN** the answers hold a key the script does not know
- **THEN** a warning names it and the key is ignored

### Requirement: HOME-036 Repo must hold the base files
`scripts/configure` SHALL exit 3 when `jq` is missing, a template under `templates/` is missing, or `CLAUDE.md` lacks the fourth buffer line that ends the base block and its buffer.

#### Scenario: Not a base clone
- **WHEN** the repo has no `CLAUDE.md` holding the fourth buffer line
- **THEN** the script exits 3 and says to take it from the base first

### Requirement: HOME-037 Only the listed files are written
`scripts/configure` SHALL write only `home.config`, `.local/config`, the home section of `CLAUDE.md` below the buffer, `.claude/settings.json` with `enabledPlugins` from the answers, missing `.gitignore` lines, `wiki/index.md` and `DECISIONS.md` when absent, `wiki/howto/accounts.md` when several accounts are declared, the repo-local `core.hooksPath`, the removal of tracked `base-only` paths and the `origin` and `base` remotes.

#### Scenario: Base block untouched
- **WHEN** configure rewrites `CLAUDE.md`
- **THEN** every line up to and including the fourth buffer line is unchanged and only the home section is replaced

#### Scenario: Existing wiki kept
- **WHEN** `wiki/index.md` already exists
- **THEN** it is not overwritten

#### Scenario: Machine file keeps foreign lines
- **WHEN** `.local/config` holds a key configure does not manage
- **THEN** that line is kept

### Requirement: HOME-038 Idempotent setup
Running `scripts/configure` twice with the same answers SHALL produce the same files and rewrite a file only when its content changes.

#### Scenario: Second run
- **WHEN** configure runs again with unchanged answers
- **THEN** no file is reported as written

### Requirement: HOME-039 Terminal helpers only on a capable device
`scripts/configure` SHALL keep `terminal_helpers=off` when it was answered `on` but the device check (macOS, its scripting bridge and the supported terminal application) fails, and say so in the keys-used report.

#### Scenario: Not macOS
- **WHEN** `terminal_helpers=on` is answered on a Linux machine
- **THEN** `.local/config` holds `terminal_helpers=off` and the report notes the failed device check

### Requirement: HOME-040 Account rows are labels only
With `accounts.multi=yes`, `scripts/configure` SHALL accept only account rows of three fields, `label | what it serves | where the mapping lives`, and reject any row holding an address.

#### Scenario: Address in a row
- **WHEN** an account row contains `@`
- **THEN** it is reported as invalid and nothing is written

### Requirement: HOME-041 Keys-used report
After writing, `scripts/configure` SHALL print every key it used with its value and whether it came from an answer or a default.

#### Scenario: Default accepted
- **WHEN** `limits.threshold` was not answered
- **THEN** the report shows `limits.threshold=90 (default)`

### Requirement: HOME-042 Two config files
The config reader SHALL read `key=value` lines from `.local/config`, which overrides the committed `home.config`, ignore `#` comments, expand a leading `~/`, and export `gh.config_dir` as `GH_CONFIG_DIR` when set.

#### Scenario: Machine override
- **WHEN** `home.config` holds `limits.mode=none` and `.local/config` holds `limits.mode=soft`
- **THEN** the scripts read `soft`

#### Scenario: Account per home
- **WHEN** `gh.config_dir` is set in `.local/config`
- **THEN** every script of the home calls `gh` with that config directory

### Requirement: HOME-074 A failed label step is reported after the files are written
When `--labels` is given and the labels cannot be created, `scripts/configure` SHALL keep the files it wrote, exit 4 and end with one line saying the labels are not created and whether the repository was not found, this login has no permission to create labels, or GitHub refused for another reason, with the matching next step.

#### Scenario: The repository does not exist yet
- **WHEN** `scripts/configure --answers <file> --labels` runs for a repository that does not exist on GitHub
- **THEN** every file is written, the script exits 4 and its last line says the repository was not found: create it (private), commit, push, then run `scripts/labels`

#### Scenario: No permission to create labels
- **WHEN** the repository exists but creating a label returns HTTP 403
- **THEN** the script exits 4 and its last line says this login has no permission to create labels: run `gh auth refresh -s repo`, then `scripts/labels`

### Requirement: HOME-075 Base-only paths leave the home
On a successful run in a git repo with a `base.manifest`, `scripts/configure` SHALL remove with `git rm` every `base-only` path that is still tracked and name each one it removed.

#### Scenario: Fresh clone of the base
- **WHEN** configure runs in a clone that still tracks `openspec/` and `README.md`
- **THEN** both are removed from the index and the folder, each is named in the output, and paths listed `flows` stay

### Requirement: HOME-076 Origin points at the home's own repo
When `origin` is the URL in `base.url`, `scripts/configure` SHALL rename it to `base` with its push URL `DISABLED` and add `origin` as `https://github.com/<repo>.git` (only re-pointing `origin` when `base` already exists, and adding `origin` when none exists), and never push.

#### Scenario: Fresh clone of the base
- **WHEN** configure runs in a clone whose `origin` is the base
- **THEN** `base` is the base URL with push `DISABLED`, `origin` is the repo of the answers for fetch and push, and the output says where origin now points

#### Scenario: Base remote already present
- **WHEN** `origin` is the base and a `base` remote already exists
- **THEN** `origin` is set to the repo of the answers with no separate push URL and `base` keeps push `DISABLED`

#### Scenario: Origin already the home's
- **WHEN** `origin` is any URL other than the base
- **THEN** it is left unchanged

### Requirement: HOME-077 A failed write or git step stops the run
`scripts/configure` SHALL check the result of every file write and every git step and, on a failure, exit 3 naming the file or step, without reporting it as written.

#### Scenario: Unwritable file
- **WHEN** `home.config` cannot be written
- **THEN** the script exits 3 with `cannot write home.config` and never prints `wrote home.config`

### Requirement: HOME-079 The skill asks only what it cannot know
The `configure` skill MUST ask, in plain words without key names, only for the owner, what the home is for, what must never enter it, the owner's own rules, the repo name, the file language and a team board, at most four questions per round, and set every other key to its default without asking.

#### Scenario: Newcomer
- **WHEN** a person who knows none of the settings runs the skill
- **THEN** they are asked at most those seven things as open or recommended-first questions, and the closing message lists the defaults and says any can be changed later by telling the agent

#### Scenario: Cloud session
- **WHEN** the session runs in the cloud or the person has no terminal
- **THEN** terminal helpers are off and nothing about terminals or this machine is said
