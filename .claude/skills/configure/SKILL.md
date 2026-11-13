---
name: configure
description: Make this repo the user's own home from the base. Use when someone says "configure", "set up my home", "make a home from this base", "onboard me", after cloning the base, or with an answers file ("configure --answers <file>") for an unattended setup.
---

# configure

One code path: `scripts/configure --answers <file> [--labels]`. Interactive mode only collects the answers. `templates/answers.example` lists every key with an example.

## With an answers file
Run `scripts/configure --answers <file> --labels`. Exit 2 lists every missing or invalid key: ask for exactly those (or report them when unattended) and run again. Exit 3: the repo is not ready (no `CLAUDE.md` with the base block and buffer, or a template missing) or a write or git step failed; the line names the file or step: fix that and run again. Exit 4: the files are written but the labels are not; the last line says why, tell the person that cause in one sentence:
- "was not found on GitHub": the repo does not exist yet (or this login cannot see it): create it (private), commit, push, then `scripts/labels`.
- "no permission to create labels": the repo exists but this login may not create labels: `gh auth refresh -s repo`, then `scripts/labels`.
- Anything else: GitHub refused for another reason (the line above names it); run `scripts/labels` once it is fixed.
A newcomer's repo usually does not exist yet, so "was not found" is the normal first run: go straight to the closing checklist. Never say the labels exist after exit 4.

## Before asking: where is this session?
- Cloud or web session (`CLAUDE_CODE_REMOTE` is set, or the person says they have no terminal or work only in the browser): `terminal_helpers=off`; never mention terminals, tabs or this machine; do the commit and push steps yourself in the session instead of handing over commands.
- Linux, or macOS without iTerm2: `terminal_helpers=off`, no discussion.
- macOS with iTerm2: `terminal_helpers=on`; the script's device check keeps `off` if it fails. Do not ask.
- If the person asks about Codex, run `command -v codex` and answer from it: the home works with Codex because `AGENTS.md` is the same file as `CLAUDE.md` and the skills folder is shared; if the command finds nothing, say Codex is not installed here and works once it is.

## Interactive: ask only these
Use the surface's ask tool, in the language the person writes in, in plain everyday words. Never show a key name or the words labels, hooks, plugins, dreams, proactivity, limits, config, MCP, worker, orchestrator. At most four questions per ask call; each item shown, even inside a bundle, counts as one question. Skip anything already in `.local/answers` from an earlier run.

| Ask (plain words) | Key | How |
|---|---|---|
| "Who owns this home? Your name, or the names of the people who share it." | `owner.names` | Open question. Never pre-fill from the OS user, git identity or GitHub login. |
| "What is this home for? One line." | `home.domain` | Open question; an example from their own words is fine. |
| "What must never be put in it?" | `home.boundary` | Open question. |
| "Any rules of your own the assistant should always follow here? None is fine." | `home.rules` | Open question. Write only rules the person stated, in their meaning; never invent or pre-fill one. Zero is valid. |
| "What should the GitHub repository for this home be called?" | `repo` | Recommend `<GitHub login>/<short-name>-home` first; it must not be the base. |
| "Which language should the files be written in?" | `lang.files` | Recommend English first. |
| "Do you use a team board for tasks? Which one?" | `tracker.board` | `none` or the board's name in lower case. |

## Defaults, set silently
Write these without asking; they all appear in the closing list.
- `base.url`: the URL of the `base` remote if it exists, otherwise of `origin` (the base they cloned).
- `lang.owner`: the language the person writes in.
- `terminal_helpers`: from the section above.
- `tracker.board_write=ask-first` when a board is named; `labels.needs_owner=needs-owner`.
- `limits.mode=none`, `proactivity.mode=assigned`, `dreams.mode=manual`, `plugins=` (empty), `accounts.multi=no`, launch keys empty, no related homes.
Ask about any of these only when the person brings the topic up.

Write every answer and default as `key=value` lines to `.local/answers` (gitignored; repeatable keys one line each), then run `scripts/configure --answers .local/answers --labels`. The script removes the base's own files from the home and points `origin` at the new repo (the base becomes `base`, push disabled); it never pushes.

## Finish
1. Completeness check: every key from the ask table has an answer; all others may be defaults.
2. Tell the person, in their language and without key names, the defaults in one short list (where the base lives, the language used with them, terminal helpers on or off (leave this item out in a cloud or web session), no usage limits, the assistant works only on tasks given to it, the nightly review runs only when asked, no add-ons, one account), and that any of them can be changed later: "just tell the agent".
3. Print this checklist, in their language; in a cloud or web session do steps a to d yourself:
   a. Create the private repository `<repo>` on GitHub.
   b. Commit the written files.
   c. Push: `git push -u origin HEAD`.
   d. Create the labels: `scripts/labels` (already done when the run printed `labels: ok`).
   e. Open a session in the home and say "status" (on a computer, accept the trust prompt once; on the web, start a new session on the new repo).
