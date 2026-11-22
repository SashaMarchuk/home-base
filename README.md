# home-base

A base for "home" repos. A home is one plain git repo per area of your work (all of it, one company, one client, a side project) that Claude Code or the Codex CLI opens as that area's orchestrator: it takes your requests, keeps every task as a GitHub issue, starts worker sessions and tells you what needs you.

- **One task, one issue**, in the home that owns the work. `scripts/home-log` writes the record: one comment per session run, claimed with a label, finished with one final comment. The GitHub app on a phone is enough to see what runs and to answer questions.
- **Git holds knowledge, not state:** rules (`CLAUDE.md`; `AGENTS.md` is a symlink to it for Codex), skills, small bash scripts, a markdown wiki and an append-only `DECISIONS.md`. No database, no daemon, no state file.
- **Homes work together:** a request that belongs to another home gets its one issue there; a parent home shows its children's issues, questions and sessions in one status.
- **Safe by default:** hooks block killing processes by pattern, force-pushing main, switching CLI accounts and writing personal values (cards, phone numbers, IBANs, document numbers, tokens) into tracked files. The same checks run as a git pre-commit hook and in CI.

## What you need

- macOS or Linux with `bash`, `git`, `jq`, `python3` and `perl`.
- The GitHub CLI, logged in: `gh auth login` (`gh api user` prints your login).
- Claude Code (`claude`) or the Codex CLI (`codex`), or both: a home works with either from the same files.
- Optional, macOS only: iTerm2, for the terminal helpers that open and close worker tabs for you. Without it you get the worker prompts to paste yourself.

## Two kinds of home

Start with one. Most people end up with a personal home plus one domain home per company, client or project.

### A. A personal home

The orchestrator over everything you do: it routes each request to the home that owns it and shows one status across all of them.

1. Clone this repo (do not use "Use this template": it cuts the shared history, and base updates stop merging):
   ```
   git clone <this repo's URL> ~/homes/personal-home && cd ~/homes/personal-home
   ```
2. Start your agent there (`claude` or `codex`; in Codex, trust the folder and, after the first start, type `/hooks` once to trust the home's hooks) and say `configure`. It asks a few plain questions: who owns the home, what it is for ("everything I do; routes work to my other homes"), what must never enter it, your own rules, the repository name, the file language, a team board. Everything else gets a default you can change later by telling the agent.
3. It writes `home.config`, `.local/config`, the home section of `CLAUDE.md`, the hooks settings and a starting wiki, removes the base-only files, renames `origin` to `base` (push disabled) and points `origin` at your new private repo. Whatever it could not do itself (create the repo, push, add the labels) it lists as lines to run.
4. Say `status`.

Unattended instead: fill a copy of `templates/answers.example` and run `scripts/configure --answers <file> --labels`.

### B. A domain home

The home of one company, client or project, for example `work-home` for your job or `client-home` for one client. Same steps as A in a new folder; answer the purpose with that domain ("everything for Acme: tickets, releases, reviews") and the boundary with what must stay out ("nothing from other clients, nothing personal"). A session opened there only ever sees that domain.

## Wire homes together

Each home names the homes it works with in its own `home.config`, one block per home, then commits it:

```
homes.<name>.repo=<owner>/<repo>          its GitHub repo
homes.<name>.path=~/homes/<folder>        its local clone on this machine (for status and to start its orchestrator)
homes.<name>.role=child                   parent | child | peer
homes.<name>.topics=word,word,two words   requests about these go to that home
```

- **parent / child:** the parent routes work down and shows the child's issues, questions and sessions in its status (`scripts/home-status --all`). The child owns its queue and closes its own issues.
- **peer:** a home of equal rank; a hand-off to it carries a brief and links only, never the other domain's details.
- **topics:** only the routing home reads them. A request that fits one home goes there; fits none, stays here; fits two, you get one question. They are committed in the routing home's `home.config`, so use generic words ("sprint", "release", "newsletter"), never client, company or people names: `scripts/checks/run` blocks a term of the routing home's boundary list (`guard.boundary_terms`) there like in any other committed file.

Tell the agent ("add my work home as a child: repo you/work-home, folder ~/homes/work-home, topics standup, sprint, acme"), or put the lines in the answers file before `configure`.

### Example: three homes

`personal-home` is the parent of `work-home` (a job) and `club-home` (a volunteer club). In `personal-home/home.config`:

```
homes.work.repo=you/work-home
homes.work.path=~/homes/work-home
homes.work.role=child
homes.work.topics=acme,sprint,standup,release,on-call
homes.club.repo=you/club-home
homes.club.path=~/homes/club-home
homes.club.role=child
homes.club.topics=club,members,newsletter,events
```

In `work-home/home.config` and `club-home/home.config`, each names the parent only:

```
homes.personal.repo=you/personal-home
homes.personal.path=~/homes/personal-home
homes.personal.role=parent
```

Now, in the personal home, "prepare the release notes for Acme" opens one issue in `work-home` (none in `personal-home`) and starts the work home's orchestrator; "draft the club newsletter" goes to `club-home`; "renew my passport" stays in `personal-home`. `status` in the personal home lists all three homes' issues, your open questions and the running sessions. A task you start directly in `work-home` shows up there too. Each home can use its own GitHub login: set `gh.config_dir=<dir>` in that home's `.local/config`. `home-status` reads a related home from its own folder with that home's `gh.config_dir`, never with the calling home's; an account picked per folder by your shell's startup file does not reach it, so set `gh.config_dir` there.

## Take base updates

The base ships releases: git tags `vX.Y.Z` ([SemVer](https://semver.org): a major release asks you to do something by hand and says what in its notes), each with a section in `CHANGELOG.md` and a GitHub release. `main` is always the newest release. `VERSION` in your home says which release it is on. Nothing updates by itself: you choose when.

```
scripts/base-update --check            # this home's release, the newest one, the target
scripts/base-update --dry-run          # what an update would change; changes no file or commit
scripts/base-update                    # update to the newest release (or to base.pin)
scripts/base-update 1.4.0              # move to that release (an older one too)
scripts/base-update --rollback         # back to the release before the last update
```

- It refuses to run with uncommitted changes to tracked files, and stops with exit 3 and changes nothing when the base cannot be reached.
- It makes one commit and never pushes: look at it, run `scripts/checks/run`, then `git push`.
- It sets every path the base owns (`base.manifest`) to the release's exact content: the base folders and files, and the base block of `CLAUDE.md` (your home section below the `BUFFER` lines stays as it is). It never touches anything else; the base-only paths (its README, openspec) never enter your home, and your own files at those paths stay.
- `--check` and `--dry-run` change no file and no commit; they only fetch the release tags into `refs/base-tags/`.
- **Pin a version:** put `base.pin=1.4` in `home.config` (or `.local/config` for one machine only). Updates then stay on the newest `1.4.x`; `base.pin=1.4.2` holds exactly that release. Remove the line to follow the newest release again.
- **Roll back:** `scripts/base-update --rollback` makes a new commit with the previous release's content. It never resets or force-pushes, so it is safe after a push and in a home that several people share. One step only; run an update to move forward again.
- **First update of a home made before releases** (no `VERSION` file): the command finds the base commit your home last merged and starts from there. If your home has no copy of the command yet, run it once from the release itself:
  ```
  git fetch base '+refs/tags/v*:refs/base-tags/v*'
  bash <(git show refs/base-tags/v1.0.0:scripts/base-update) 1.0.0
  ```
- In an agent session, say `update from base` (the `base-update` skill runs the same command). A session start prints `SWEEP base-ahead ... base release vX.Y.Z is out` when there is one to take.

## Your own rules and settings

A base update never touches these, so put everything of yours here and never edit a base file:

| Yours | Where |
|---|---|
| Rules for the agent, standing approvals | the home section of `CLAUDE.md`, below the four `BUFFER` lines. A rule there may replace a base rule it names. |
| Settings shared by everyone who uses the home | `home.config` |
| Settings of one machine, secrets paths | `.local/config` (gitignored) |
| Your own scripts | `tools/` |
| Your own skills | `.claude/skills/<a name the base does not use>/` |
| Knowledge and decisions | `wiki/`, `DECISIONS.md` |

If you edited a base-owned file anyway, the next update keeps your text safe: it saves your edits as a patch in `.local/base-update/<from>-to-<to>-<time>.patch`, applies the release, lists the files and says where that text belongs. Files you added inside a base folder (for example `scripts/my-tool`) stay where they are and are listed; move them to `tools/`. A fix the base itself needs goes to the base as an issue or a pull request.

## What never goes into a home

Git holds links and knowledge only. Never commit secrets or tokens, personal values (phone, passport or tax numbers, cards, IBANs), call recordings or raw transcripts, or data copied from another home or client. The checks block the patterns they know; the rest is on you. `.local/` (machine settings, registry, scratch) is gitignored. A voice-interview transcript (`scripts/voice-collect`) goes to a path outside git.

## Troubleshooting

- **`gh` uses the wrong account:** set `gh.config_dir` in that home's `.local/config`; every script exports it as `GH_CONFIG_DIR`. Never switch accounts.
- **Status labels are missing:** run `scripts/labels` in the home (`gh auth refresh -s repo` first if it says the login may not manage labels).
- **`home-log` exits 4:** the text looked like a personal value or another domain's term; change the wording.
- **Codex ignores the rules or hooks:** trust the folder, then `/hooks` once.
- **No tabs open:** the terminal helpers are on only on macOS with iTerm2: `scripts/configure --set terminal_helpers=on`.
- **Status says `sessions: unknown`:** add `homes.<name>.path` for that home on this machine.
- **Status says `issues: cannot read <repo>`:** the login of that home (`gh.config_dir` in its `.local/config`) cannot read the repo.

## What is where

| Path | What |
|---|---|
| `CLAUDE.md` | base block (rules, where things live), a fixed four-line buffer, then your home section |
| `.claude/skills/` | `orchestrate`, `task`, `status`, `wiki`, `decide`, `configure`, `dreams`, `base-update` (`.agents/skills` is the same folder, for Codex) |
| `scripts/` | `home-log`, `home-sweep`, `home-status`, `labels`, `limits`, `configure`, `base-update`, `voice-collect`, `checks/run`, `hooks/`, `term/term.sh`, `tests/` |
| `.codex/` | `hooks.json`: the same hooks for Codex (the home's own `config.toml` sits beside it) |
| `templates/` | the files `configure` writes into a home |
| `base.manifest` | which paths the base owns and which stay in the base only |
| `VERSION` | the base release a home is on |
| `CHANGELOG.md` | what each release changed (base only) |
| `openspec/` | the base's requirements (base only) |

The terminal helpers (`scripts/term/term.sh`) open, freeze and thaw Claude Code tabs only. `survey`, `state`, `send`, `park`, `resume` and `close` also run from a Codex session, and park, resume and close of a Codex tab (once its SessionStart hook has recorded its thread id) are built and tested on a fake terminal only, not yet checked on a real Codex tab. `term.sh finished` lists, without touching anything, which tabs `close` would accept. After a reboot or a crash, `term.sh reconcile` marks a registry entry lost (never closed) when its session runs nowhere it was recorded: its process is gone and its tab is gone or no longer runs it (a window iTerm2 restores with the same tab ids and fresh shells counts as gone). `term.sh reopen --lost` reopens lost entries in their group windows with their resume lines (sessions already running, and entries whose issue is closed, finished, released or taken over by another run, are skipped), `term.sh forget <session id>` closes a lost entry that must not come back, `term.sh adopt <tty>|--all` records tabs this home did not open (typing nothing; they stay the owner's tabs), and `term.sh regroup --dry-run` prints which registered tabs sit outside their group's window: the iTerm2 AppleScript backend cannot move a tab, so regroup moves nothing. These five are tested on a fake terminal only. A session is found by its process name: the kill guard sees only a process named exactly `claude` or `codex`, and the helpers one named as `launch.command` (default `claude`) or `codex`; a wrapper under another name is not seen. The hooks and the session-end stub support Claude Code and Codex; Codex runs them once you trust the folder and, with `/hooks`, the home's hooks. Known limit: a Claude Code session started from a Codex shell inherits `CODEX_THREAD_ID`, so `home-log` records it as a Codex run and `term.sh open`, `freeze` and `thaw` refuse to run in it.

Run `scripts/tests/run.sh` to test the scripts (needs bash, jq, perl, python3, git; no network; a full run takes a few minutes).

## Making a release (base maintainers)

1. Add a section `## [X.Y.Z] - <date>` at the top of `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com): Added, Changed, Fixed, Removed; a major release adds "Do by hand").
2. Write `X.Y.Z` into `VERSION`, commit, and tag the commit: `git tag -a vX.Y.Z -m vX.Y.Z`.
3. Push `main` and the tag together, then make the GitHub release from that changelog section: `gh release create vX.Y.Z --verify-tag --title vX.Y.Z --notes-file <section>`.

`main` moves only at a release, so a fresh clone is always a release.

Licence: MIT (see LICENSE)
