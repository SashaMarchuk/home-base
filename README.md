# home-base

A base for "home" repos: one plain git repo per domain of your work (personal, a company, a side business) that a coding agent opens as that domain's orchestrator. It works with Claude Code and the Codex CLI from the same files.

- **Every task is a GitHub issue** in the home that owns it. One script, `scripts/home-log`, writes the record: one comment per session run, claimed with a label, finished with one final comment. A phone with the GitHub app is enough to see what runs and to answer questions.
- **Git holds knowledge, not state:** rules (`CLAUDE.md`, with `AGENTS.md` as a symlink), eight skills, small bash scripts, a markdown wiki and an append-only `DECISIONS.md`. No database, no daemon, no state file.
- **Homes talk to each other** through issues: a parent home opens an issue in a child or peer home and starts that home's orchestrator; the child owns its queue; the parent reads the result.
- **Safety by default:** hooks block killing processes by pattern, force-pushing main, switching CLI accounts and writing personal values (cards, phone numbers, IBANs, document numbers, tokens) into tracked files. The same checks run as a git pre-commit hook and in CI for surfaces where hooks do not load.

## Make your own home

1. Clone this repo into a new folder and rename the remote:
   ```
   git clone <this repo's URL> my-home && cd my-home
   git remote rename origin base
   git remote set-url --push base DISABLED
   ```
   Do not use "Use this template": it cuts the shared history, and base updates stop merging.
2. Remove the base-only paths (`openspec/`, `README.md`, `.github/workflows/base-checks.yml`) in your first commit.
3. Open a session in the folder and run the `configure` skill. It asks a few questions (owner, languages, tracker, other homes, optional terminal helpers) and writes your `home.config`, `.local/config`, the home section of `CLAUDE.md`, `.claude/settings.json` and a starting wiki. To configure without questions, fill `templates/answers.example` and run `scripts/configure --answers <file>`.
4. Create a private repo for your home, add it as `origin`, push, and run `scripts/labels`.

## Take base updates

In your home, the `base-update` skill fetches `base`, merges, removes base-only paths again, and settles conflicts: a clean merge is committed; a conflict only in base-owned paths takes the base's side and saves your dropped diff in an issue; anything else stops and asks you. A session start prints "base/main is N commits ahead" when there is something to take.

## What is where

| Path | What |
|---|---|
| `CLAUDE.md` | base block (rules, where things live), a fixed four-line buffer, then your home section |
| `.claude/skills/` | `orchestrate`, `task`, `status`, `wiki`, `decide`, `configure`, `dreams`, `base-update` |
| `scripts/` | `home-log`, `home-sweep`, `labels`, `limits`, `configure`, `checks/run`, `hooks/`, `term/term.sh`, `tests/` |
| `templates/` | the files `configure` writes into a home |
| `base.manifest` | which paths the base owns and which stay in the base only |
| `openspec/` | the base's requirements |

Run `scripts/tests/run.sh` to test the scripts (needs bash, jq, perl, python3, git; no network; a full run takes a few minutes).
