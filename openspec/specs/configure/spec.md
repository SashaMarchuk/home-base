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
`scripts/configure` SHALL write only `home.config`, `.local/config`, the home section of `CLAUDE.md` below the buffer, `.claude/settings.json` with `enabledPlugins` from the answers, missing `.gitignore` lines, the answers file's `terminal_helpers` line, `wiki/index.md` and `DECISIONS.md` when absent, `wiki/howto/accounts.md` when several accounts are declared, the repo-local `core.hooksPath`, the removal of tracked `base-only` paths and the `origin` and `base` remotes.

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
- **THEN** the script exits 4 and its last line says this login has no permission to manage labels, with the fix on a computer (`gh auth refresh -s repo`) and in a web session (give the GitHub app access to the repository), then `scripts/labels`

### Requirement: HOME-075 Base-only paths leave the home
In a git repo with a `base.manifest`, `scripts/configure` SHALL delete from the folder every `base-only` path that is still tracked, before any git step, name each one it removed, and drop them from the index in the git steps.

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
`scripts/configure` SHALL check the result of every file write and every git step and, on a failure other than a refused git permission, exit 3 naming the file or step and git's own error, without reporting it as written.

#### Scenario: Unwritable file
- **WHEN** `home.config` cannot be written
- **THEN** the script exits 3 with `cannot write home.config` and never prints `wrote home.config`

### Requirement: HOME-079 The skill asks only what it cannot know
The `configure` skill MUST ask, in plain words without key names, only for the owner, what the home is for, what must never enter it, the owner's own rules, the repo name, the file language and a team board, in exactly two ask calls (owner, purpose, never-allowed and own rules first; repo name, file language and board second), and set every other key to its default without asking.

#### Scenario: Newcomer
- **WHEN** a person who knows none of the settings runs the skill
- **THEN** they are asked those seven things in two calls, and the closing message lists the defaults as bullet lines, starting with "Updates to this setup come from: <url>", and says any can be changed later by telling the agent

#### Scenario: Cloud session
- **WHEN** the session runs in the cloud or the person has no terminal
- **THEN** terminal helpers are off and nothing about terminals or this machine is said

#### Scenario: Not macOS
- **WHEN** `uname -s` does not print `Darwin`
- **THEN** terminal helpers are off, the terminal application is never mentioned and the closing list says only "opening terminal tabs: off"

### Requirement: HOME-083 The answers file keeps the effective terminal helpers value
When the device check turns an answered `terminal_helpers=on` into `off`, `scripts/configure` SHALL rewrite the `terminal_helpers` line of the answers file to `off` and say so.

#### Scenario: Device check fails
- **WHEN** the answers hold `terminal_helpers=on` and the device check fails
- **THEN** the answers file and `.local/config` both hold `terminal_helpers=off`, and a second run changes neither

### Requirement: HOME-084 Board write rule only with a board
`scripts/configure` SHALL write a value for `tracker.board_write` to `home.config` only when `tracker.board` names a board, and leave it empty when the board is `none`.

#### Scenario: No board
- **WHEN** the answers hold `tracker.board=none` and `tracker.board_write=ask-first`
- **THEN** `home.config` holds `tracker.board_write=` with no value

### Requirement: HOME-085 The skill works from the repo root
The `configure` skill SHALL find the repo root with `git rev-parse --show-toplevel`, write the answers and run the script only there, and name that folder by its absolute path in the closing steps.

#### Scenario: Started in a subfolder
- **WHEN** the session starts in a subfolder of the home
- **THEN** no file is created in the subfolder and the closing steps name the absolute repo root

### Requirement: HOME-086 Boundary and rules are the person's own words
The `configure` skill SHALL ask for what must never enter the home and for the owner's rules as free text with no options or example answers, and record every rule the answer mentions without judging any redundant.

#### Scenario: Rule the person thinks is covered
- **WHEN** the person answers that they have no rules except one the defaults may already cover
- **THEN** that rule is written to the home section

### Requirement: HOME-087 The closing lists only what is left
The `configure` skill SHALL close with only the steps still left, in plain words and each chosen from the actual result, and in a cloud or web session name what is not done and the one browser action instead of any command.

#### Scenario: Labels created and repo exists
- **WHEN** the run printed `labels: ok` and the repository exists
- **THEN** neither creating the repository nor adding the status tags is listed

#### Scenario: Web session push fails
- **WHEN** a push the skill tries in a web session fails
- **THEN** it says what is not done, with no cause, and gives one action: create the repository if it is missing, give the GitHub app access to it, then come back to this session and say "finish the setup", with no command

### Requirement: HOME-088 Exit 4 names only the printed cause
After `scripts/configure` exits 4, the `configure` skill SHALL state only the cause the last line printed, with its fix, in one sentence, without other causes or a conditional fix.

#### Scenario: No permission
- **WHEN** the last line says this login has no permission to manage labels
- **THEN** the person hears that cause and the fix for their surface, and nothing about other possible causes

### Requirement: HOME-089 Finishing the setup in a later session
When asked to "finish the setup", the `configure` skill SHALL run only the steps still pending (upload, status tags) in a configured home, and in a repository without the base files run nothing and point the person to the session where the setup started or to the base with their pasted answers.

#### Scenario: Upload retried in the same session
- **WHEN** the upload failed in a web session and the person comes back to it and says "finish the setup"
- **THEN** the session uploads the files and adds the status tags without asking anything again

#### Scenario: Empty repository
- **WHEN** "finish the setup" is said in a new session on a repository without `scripts/configure`
- **THEN** no script is run and the person is told to return to the first session, or to open the base again, say "set it up" and paste the answers block

### Requirement: HOME-090 Setup comes before the record of work
Until `home.config` exists, a session SHALL treat the `configure` skill as its only task, open no issue and not use `scripts/home-log`, and end its turn with the questions when it must ask.

#### Scenario: A surface without an ask tool
- **WHEN** configure runs on a surface that has no ask tool
- **THEN** the session finishes its checks and the numbered questions are the final message of the turn, with no progress or status message before or after them and no reference to "the questions above"

### Requirement: HOME-091 Git settings are changed last
`scripts/configure` SHALL finish every step outside `.git` before any git step and, when git refuses a step for lack of permission (`Operation not permitted`, `could not lock config file`, read-only), exit 5 with one line saying the files are written, this session may not change the repository's git settings, and `scripts/configure --answers <file>` is to be run from the person's own terminal (or allowed), then continue.

#### Scenario: Git config refused
- **WHEN** `git config` fails with "could not lock config file" during a run on a fresh clone of the base
- **THEN** every file is written, the base-only paths are gone from the folder, the script exits 5 with that one line, and a rerun with permission sets the hooks path, the index and the remotes

### Requirement: HOME-092 Several questions in one numbered list
When one ask call carries several questions, the `configure` skill SHALL send them as one numbered free-text list with each recommendation inside its own question, and use an options list only for a call holding a single question.

#### Scenario: Second round
- **WHEN** the skill asks for the repository name, the file language and the team board together
- **THEN** it sends three numbered questions, the first two each naming its recommendation, and no options list

### Requirement: HOME-093 Session checks one command each
The `configure` skill SHALL run `echo "${CLAUDE_CODE_REMOTE:-}"` alone as its first command, run `uname -s` alone only when that printed nothing, and set terminal helpers on only when `uname -s` printed `Darwin` and `$TERM_PROGRAM` is `iTerm.app`.

#### Scenario: Terminal application installed but not used
- **WHEN** the session runs on macOS in a terminal other than iTerm2 that is installed on the machine
- **THEN** terminal helpers are off

### Requirement: HOME-094 Names exactly as typed
The `configure` skill SHALL write the owner names exactly as the person typed them, in their own script, without transliterating.

#### Scenario: Names in a non-Latin script
- **WHEN** the person gives their name in a non-Latin script and the file language is English
- **THEN** `owner.names` holds the name as typed

### Requirement: HOME-095 Creating the repository on request
When the person asks the `configure` skill to create the repository, the GitHub login works and the repository does not exist, the skill SHALL run `gh repo create <repo> --private` before the script and say in one sentence that it was created as private.

#### Scenario: Creation fails
- **WHEN** `gh repo create` fails
- **THEN** the closing list keeps the step to create the private repository, with the reason

### Requirement: HOME-096 The person's word about the repository
The `configure` skill SHALL list the step to create the repository, and give "the repository does not exist yet" as the status-tag cause, when the person said it is not created even if GitHub reports otherwise, and say "a repository with this name already exists on your account; I used it" when it was found although the person said they had not created it.

#### Scenario: Found although not created
- **WHEN** the person said they have not created the repository and `gh api repos/<repo>` finds it
- **THEN** the closing says a repository with this name already exists on their account and was used

### Requirement: HOME-097 A failed upload in plain words
When the files were saved but only the upload failed on a computer, the `configure` skill SHALL say "the files are saved on this computer but not uploaded yet", give only `cd <root> && git push -u origin HEAD`, name no cause and not use the word "commit".

#### Scenario: Push refused
- **WHEN** the commit succeeded and the push failed
- **THEN** the closing gives that sentence and the push line only

### Requirement: HOME-098 Closing after a stopped run
After `scripts/configure` exits 3 or 5 with files written, the `configure` skill SHALL say in plain words what is saved and what is not, without file names, and give the full remaining list: the command to run again, creating the repository, the upload line, the status tags and opening a session with "status".

#### Scenario: Git settings refused
- **WHEN** the script exits 5
- **THEN** the closing names no file such as `.git/config` and lists every remaining step, starting with the command to run from the person's own terminal

### Requirement: HOME-099 No retry of a refused git step
On Codex the `configure` skill SHALL run `scripts/configure` asking for elevated permission because it changes git settings, and after exit 5 hand over the printed line without running the script again in that session.

#### Scenario: Permission refused on Codex
- **WHEN** the script exits 5 in a Codex session
- **THEN** the session does not run it again and gives the person the line to run from their own terminal

### Requirement: HOME-100 Codex in a cloud session
Asked about Codex in a cloud or web session, the `configure` skill SHALL say the home works with Codex as-is when the same repository is opened with Codex, because Codex reads the same rules file and the same skills, and that there is nothing to install.

#### Scenario: Codex question in the browser
- **WHEN** the person asks about Codex in a web session
- **THEN** the answer gives the reason and asks for no installation
