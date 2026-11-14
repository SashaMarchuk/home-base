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
- **THEN** every file is written, the script exits 4 and its last line says the repository was not found: create it (private), then run one line starting with `cd <root> &&` that runs `scripts/labels`

#### Scenario: No permission to create labels
- **WHEN** the repository exists but creating a label returns HTTP 403
- **THEN** the script exits 4 and its last line says this login has no permission to manage labels, with the fix in a web session (on github.com/settings/installations open Claude, Configure, and add the repository with read and write access, then `scripts/labels`) and, for a computer, one line starting with `cd <root> &&` that runs `gh auth refresh -s repo` and then `scripts/labels`

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
The `configure` skill MUST ask, in plain words without key names, only for the owner, what the home is for, what must never enter it, the owner's own rules, the repo name, the file language and a team board, in at most two ask calls (owner, purpose, never-allowed and own rules first; repo name, file language and board second, skipping what the first reply already settles), and set every other key to its default without asking.

#### Scenario: Newcomer
- **WHEN** a person who knows none of the settings runs the skill
- **THEN** they are asked those seven things in at most two calls, and the closing message gives as bullets only where improvements can be pulled from, the languages and whether the assistant opens a new terminal tab when a task needs its own window, puts every other default into one plain sentence, and says any can be changed by telling the assistant

#### Scenario: Cloud session
- **WHEN** the session runs in the cloud or the person has no terminal
- **THEN** terminal helpers are off and nothing about terminals or this machine is said

#### Scenario: Not macOS
- **WHEN** `uname -s` does not print `Darwin`
- **THEN** terminal helpers are off, the terminal application and Cmd+Space are never mentioned, the closing says "The assistant does not open terminal tabs for you" and tells the person to open a terminal, paste the line and press Enter

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

### Requirement: HOME-086 Boundary and rules are the person's own answer
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
- **THEN** it says what is not done, with no cause, and gives one action: create the repository if it is missing, add it with read and write access on github.com/settings/installations under Claude, then come back to this session and say "finish the setup", with no command

### Requirement: HOME-088 Exit 4 names only the printed cause
After `scripts/configure` exits 4, the `configure` skill SHALL state only the cause the last line printed, in one sentence without other causes, and on a computer give the line that last line ends with as the status tags step, which after a `pending:` line is also the single upload step.

#### Scenario: No permission
- **WHEN** the last line says this login has no permission to manage labels
- **THEN** the person hears that cause once, the status tags step holds the printed line, and nothing is said about other possible causes

### Requirement: HOME-089 Finishing the setup in a later session
When asked to "finish the setup", the `configure` skill SHALL run only the steps still pending (upload, status tags) in a configured home, and in a repository without the base files run nothing and point the person to the session where the setup started or to the base with their pasted answers.

#### Scenario: Upload retried in the same session
- **WHEN** the upload failed in a web session and the person comes back to it and says "finish the setup"
- **THEN** the session uploads the files and adds the status tags without asking anything again

#### Scenario: Empty repository
- **WHEN** "finish the setup" is said in a new session on a repository without `scripts/configure`
- **THEN** no script is run and the person is told to return to the first session, or to open a new session on the base address, say "set it up" and paste the answers block

### Requirement: HOME-090 Setup comes before the record of work
Until `home.config` exists, a session SHALL treat the `configure` skill as its only task, open no issue and not use `scripts/home-log`, and end its turn with the questions when it must ask.

#### Scenario: A surface without an ask tool
- **WHEN** configure runs on a surface that has no ask tool
- **THEN** the session runs every check first, its last message of the turn is the numbered questions and nothing else, and it never writes "waiting for your answers" or refers to a form

### Requirement: HOME-091 Git settings this session may not change
`scripts/configure` SHALL probe whether it may change the repository's git settings before writing anything and, when it may not, do every other step, print one line `pending: cd <root> && <the git steps still needed>` that does the rest from the person's own terminal and exit 0, keeping exit 5 with a full `cd <root> && scripts/configure --answers <file>` line for a git step refused after a successful probe.

#### Scenario: Git config refused
- **WHEN** `git config --local` fails with "could not lock config file" during a run on a fresh clone of the base
- **THEN** every file is written, the base-only paths are gone from the folder, the script exits 0 with one `pending:` line that drops those paths from the index, renames `origin` to `base` with push disabled, adds `origin` for the home's repo and sets the hooks path, and a later run with permission sets the same and prints no `pending:` line

#### Scenario: Refused after the probe
- **WHEN** the probe succeeds but a later git step is refused for lack of permission
- **THEN** the script exits 5 and its last line gives the full rerun line starting with `cd <root>`

### Requirement: HOME-092 Several questions in one numbered list
When one ask call carries several questions, the `configure` skill SHALL send them as one numbered free-text list with each recommendation inside its own question, and use an options list only for a call holding a single question.

#### Scenario: Second round
- **WHEN** the skill asks for the repository name, the file language and the team board together
- **THEN** it sends three numbered questions, each naming its recommendation, and no options list

### Requirement: HOME-093 Session checks one command each
The `configure` skill SHALL run `echo "${CLAUDE_CODE_REMOTE:-}"` alone as its first command, run `uname -s` alone only when that printed nothing, and set terminal helpers on only when `uname -s` printed `Darwin` and `$TERM_PROGRAM` is `iTerm.app`, unless the person names another terminal app they use, which gives off.

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
The `configure` skill SHALL list the step to create the repository, and give "the repository does not exist yet" as the status-tag cause, when the person said it is not created even if GitHub reports otherwise, and say "a repository with this name already exists on your account; I used it" only when the upload or a status tag write to it succeeded although the person said they had not created it.

#### Scenario: Found although not created
- **WHEN** the person said they have not created the repository and the upload to it succeeded
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

### Requirement: HOME-099 One line finishes a refused git step
When `scripts/configure` prints a `pending:` line, the `configure` skill SHALL, without pushing or running the script again, give the pending line joined with the save-and-upload command as the single upload step, explained in plain words with how to open a terminal in the repo root, without retries or talk of permission requests.

#### Scenario: Codex sandbox
- **WHEN** the script prints a `pending:` line in a Codex session
- **THEN** the closing has one upload step holding the pending line followed by `git add -A && git commit -m "Configure home" && git push -u origin HEAD`, and says this session may not change the repository's git settings, so this one line, run in a terminal in the repo root, finishes it and uploads the files

### Requirement: HOME-100 Codex works with the same home
Asked about Codex, the `configure` skill SHALL say that nothing has to be added to the home, that the same repository opened with Codex reads the same rules file and skills, and that Codex itself must be installed where the person uses it.

#### Scenario: Codex question in the browser
- **WHEN** the person asks about Codex in a web session
- **THEN** the answer says nothing has to be added to the home, gives the reason, says Codex itself must be installed where they use it, and never implies it is present

#### Scenario: Codex missing on the computer
- **WHEN** the person asks about Codex on a computer where `command -v codex` finds nothing
- **THEN** the answer adds that Codex is not installed on this computer yet

### Requirement: HOME-101 Language answers are codes
`scripts/configure` SHALL refuse a `lang.files` or `lang.owner` value that is not a two-letter language code, optionally with a region, naming the key and the expected form, and exit 2 with nothing written.

#### Scenario: Language name
- **WHEN** the answers hold `lang.files=English`
- **THEN** the script names `lang.files=English` as invalid, asks for a two-letter code and exits 2

### Requirement: HOME-102 The closing names the team board
When a team board is named, the `configure` skill SHALL say in the closing "Team board: <name>; the assistant reads it and asks before changing anything there".

#### Scenario: Board named
- **WHEN** the person names a team board
- **THEN** the closing states that board and that the assistant asks before changing anything there

### Requirement: HOME-103 The last step says how to start
The `configure` skill SHALL end every closing, whatever the outcome, with how to start working: on a computer `cd <root> && <tool>` naming only the tool this session runs in (`claude` or `codex`), the one-time trust question for the folder and typing "status"; in a cloud or web session opening a new session on the home's repository the way this one was opened and typing "status".

#### Scenario: Newcomer on a computer
- **WHEN** the closing list is given in a Claude Code session on a computer
- **THEN** its last step is `cd <root> && claude` with the absolute repo root, the trust question and "status", and Codex is not mentioned

#### Scenario: Codex session
- **WHEN** the closing list is given in a Codex session on a computer
- **THEN** its last step is `cd <root> && codex`, and Claude is not mentioned

#### Scenario: Web session
- **WHEN** the closing is given in a web session, including one whose upload failed
- **THEN** it ends with opening a new session on the home's repository and typing "status"

### Requirement: HOME-108 Free-text answers in the file language
The `configure` skill SHALL write the purpose, the boundary and the owner's rules in the file language as a faithful translation of the person's meaning, adding and dropping nothing, keeping only names in the person's own words.

#### Scenario: Answers in another language
- **WHEN** the person answers in Spanish and the file language is English
- **THEN** `home.domain`, `home.boundary` and `home.rules` hold faithful English translations, and names inside them stay as typed

### Requirement: HOME-109 One line per rule
The `configure` skill SHALL write one `home.rules` line for each separate rule, even when the person gives several rules in one sentence.

#### Scenario: Two rules in one sentence
- **WHEN** the person answers "never contact a client without asking me first, and drafts only"
- **THEN** the answers hold two `home.rules` lines and the home section lists two rules

### Requirement: HOME-110 Launch command from the surface
The `configure` skill SHALL set `launch.command` without asking, to `codex` in a Codex session and to `claude` otherwise, and `scripts/configure` writes that one-word answer to `.local/config` and refuses a value with more than one word.

#### Scenario: Setup in Codex
- **WHEN** the setup runs in a Codex session
- **THEN** `.local/config` holds `launch.command=codex`

### Requirement: HOME-111 Only the answers file is written by the skill
The `configure` skill SHALL write no file other than `<root>/.local/answers` and give the summary and the remaining steps in full in its message, never linking or naming a file or the skill and never quoting its instructions.

#### Scenario: Many steps left
- **WHEN** several steps are left after the run
- **THEN** they all appear in the message and no notes file is created

### Requirement: HOME-112 Nothing around the questions
In a question turn the `configure` skill SHALL show the questions exactly once as the only text of the turn, with no greeting, status or announcement before them and nothing after them, and on a surface without an ask tool post no message before, between or after its commands.

#### Scenario: Codex question turn
- **WHEN** round one is asked in a Codex session
- **THEN** the turn holds one message, the numbered questions, and no earlier draft or announcement

### Requirement: HOME-113 GitHub cannot be reached
When the GitHub login check cannot connect, the `configure` skill SHALL give "I could not reach GitHub from this session, so the repository is not created and the status tags are not added yet" once, as the only cause, and list creating the repository, the upload, the status tags and the start step.

#### Scenario: No connection
- **WHEN** `gh api user` fails with a connection error and the person asked for the repository to be created
- **THEN** the closing gives that sentence once and lists the step to create the repository before the upload, status tags and start steps

### Requirement: HOME-114 Exit 4 ends with the one remaining line
When the label step fails, `scripts/configure` SHALL end its last line with one command line for the person's own terminal that starts with `cd <root> &&`, holds the pending git steps with the save and upload when any are pending, and ends with `scripts/labels`.

#### Scenario: Git settings refused and repository missing
- **WHEN** the session may not change git settings and the repository is not found
- **THEN** the script exits 4 and its last line ends with the pending git steps joined with `git add -A && git commit -m "Configure home" && git push -u origin HEAD && scripts/labels`

### Requirement: HOME-115 The repository question asks whether it exists
The `configure` skill SHALL ask both what the repository is called and whether it already exists, recommending `<login>/<word>-home` with `<word>` one word from the home's purpose, saying it already exists when the GitHub lookup finds it, and treat no statement as not created.

#### Scenario: Repository already created
- **WHEN** `<login>/<word>-home` exists on the person's account
- **THEN** the question recommends it and says it already exists on their account

### Requirement: HOME-116 No board is the recommended answer
The `configure` skill SHALL ask the team board question with the recommended answer "No board (recommended for one person)".

#### Scenario: Person working alone
- **WHEN** round two is asked
- **THEN** the board question names "No board (recommended for one person)" as its recommendation

### Requirement: HOME-117 The cloud answers block in plain words
In a cloud or web session the `configure` skill SHALL give the answers block as plain labelled lines in the person's language, never as `key=value` lines.

#### Scenario: Upload failed in a web session
- **WHEN** the closing gives the answers to paste into a new session
- **THEN** they appear as lines such as Owner, Purpose, Never store, My rules, Repository, File language and Team board, with no key names

### Requirement: HOME-118 The skill saves and uploads on a computer
After `scripts/configure` exits 0 or 4 without a `pending:` line, the `configure` skill SHALL commit and push the files itself, on a computer or in the cloud, and hand the person only a step that failed.

#### Scenario: Upload succeeds
- **WHEN** the run exits 0 with no `pending:` line and the push succeeds
- **THEN** the closing lists no save or upload step

#### Scenario: Repository missing
- **WHEN** the run exits 4 because the repository was not found and the push fails
- **THEN** the closing lists creating the repository, `cd <root> && git push -u origin HEAD` and the status tags line, with no second commit

### Requirement: HOME-119 How to run a line matches the computer
Before the steps on a computer, the `configure` skill SHALL say once how to run a line: on macOS with Terminal (or iTerm when that is the terminal in use) opened by Cmd+Space, and elsewhere "open a terminal, paste the line, press Enter" with no Cmd+Space.

#### Scenario: Linux
- **WHEN** `uname -s` does not print `Darwin`
- **THEN** the closing says "To run a line: open a terminal, paste the line, press Enter." and never mentions Cmd+Space

### Requirement: HOME-120 A fallback for a refused status tags step
When the status tags step the person runs does not already hold `gh auth refresh`, the `configure` skill SHALL add "if it says this login cannot manage the tags, run `gh auth refresh -s repo` and repeat the line".

#### Scenario: GitHub could not be reached
- **WHEN** the status tags could not be tried because GitHub was unreachable
- **THEN** the status tags step carries that fallback

### Requirement: HOME-121 The cloud action keeps the repository creation
In a cloud or web session whose upload failed, the `configure` skill SHALL keep "create the private repository `<repo>` on GitHub if it is not there yet" in the one action unless an upload or status tag write to it succeeded or the person said it exists.

#### Scenario: Repository found by a lookup only
- **WHEN** `gh api repos/<repo>` succeeds but the upload fails and the person never said the repository exists
- **THEN** the one action still begins with creating the private repository if it is not there yet
