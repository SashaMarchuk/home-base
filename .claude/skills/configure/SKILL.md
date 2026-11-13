---
name: configure
description: Make this repo the user's own home from the base. Use when someone says "configure", "set up my home", "make a home from this base", "onboard me", after cloning the base, or with an answers file ("configure --answers <file>") for an unattended setup.
---

# configure

One code path: `scripts/configure --answers <file> [--labels]`. Interactive mode only collects the answers. `templates/answers.example` lists every key with an example.

## First: the repo root
Run `git rev-parse --show-toplevel` and work only in that folder (`<root>` below): run the scripts there, write `.local/answers` there, never create files or a second home in a subfolder.

## With an answers file
Run `scripts/configure --answers <file> --labels` from `<root>`. Exit 2 lists every missing or invalid key: ask for exactly those (or report them when unattended) and run again. Exit 3: the repo is not ready (no `CLAUDE.md` with the base block and buffer, or a template missing) or a write or git step failed; the line names the file or step: fix that and run again. Exit 4: the files are written but the labels are not. State only the cause the last line printed, with its fix, in one sentence; add no other cause and never make the fix conditional:
- "was not found on GitHub": the repository does not exist yet. This is the normal first run: go straight to the closing list.
- "no permission to manage labels": give the fix for this surface (on a computer `gh auth refresh -s repo`; in a cloud or web session the browser action from Finish), then the status tags.
- Anything else: the line above names what GitHub refused; the status tags can be added once it is fixed.
Never say the labels exist after exit 4.

## Before asking: where is this session?
- Cloud or web session (`CLAUDE_CODE_REMOTE` is set, or the person says they have no terminal or work only in the browser): `terminal_helpers=off`; never mention terminals, tabs or this machine; do the remaining steps yourself.
- Otherwise run `uname -s` first. Not `Darwin`: `terminal_helpers=off`, and never mention iTerm2. `Darwin` with iTerm2: `on` (the script's device check keeps `off` if it fails). `Darwin` without iTerm2: `off`. Do not ask.
- If the person asks about Codex: in a cloud or web session say "the home works with Codex as-is when the same repository is opened with Codex; nothing to install here". On a computer run `command -v codex` and answer from it: the home works with Codex because `AGENTS.md` is the same file as `CLAUDE.md` and the skills folder is shared.

## Interactive: two ask calls
Use the surface's ask tool, in the language the person writes in, in plain everyday words. Never show a key name or the words labels, hooks, plugins, dreams, proactivity, limits, config, MCP, worker, orchestrator. Ask in exactly two calls: first the owner, purpose, never-allowed and own rules; then the repository name, file language and team board. Skip anything already in `.local/answers` from an earlier run. Give examples only for the purpose, and only from the person's own words; never name a board product the person did not name.

| Ask (plain words) | Key | How |
|---|---|---|
| "Who owns this home? Your name, or the names of the people who share it." | `owner.names` | Free text. Never pre-fill from the OS user, git identity or GitHub login. |
| "What is this home for? One line." | `home.domain` | Free text. |
| "What must never be put in it?" | `home.boundary` | Free text, no options, no example answers. |
| "Any rules of your own the assistant should always follow here? None is fine." | `home.rules` | Free text, no options, no example answers. Record every rule the answer mentions, in the person's meaning, even one they think is already covered; never judge one redundant, never invent one. Zero is valid. |
| "What should the GitHub repository for this home be called? If you have already created one, give its name." | `repo` | Recommend `<GitHub login>/<short-name>-home` first; it must not be the base. |
| "Which language should the files be written in?" | `lang.files` | Recommend English first. |
| "Do you use a team board for tasks? Which one?" | `tracker.board` | `none` or the board's name in lower case. |

## Defaults, set silently
Write these without asking; they all appear in the closing list.
- `base.url`: the URL of the `base` remote if it exists, otherwise of `origin` (the base they cloned).
- `lang.owner`: the language the person writes in.
- `terminal_helpers`: from the section above.
- `tracker.board_write=ask-first` only when a board is named; `labels.needs_owner=needs-owner`.
- `limits.mode=none`, `proactivity.mode=assigned`, `dreams.mode=manual`, `plugins=` (empty), `accounts.multi=no`, launch keys empty, no related homes.
Ask about any of these only when the person brings the topic up.

Write every answer and default as `key=value` lines to `<root>/.local/answers` (gitignored; repeatable keys one line each), then run `scripts/configure --answers .local/answers --labels` from `<root>`. The script removes the base's own files from the home and points `origin` at the new repo (the base becomes `base`, push disabled); it never pushes.

## Finish
In the person's language and plain words, without key names or session tooling.
1. Completeness check: every key from the ask table has an answer; all others may be defaults.
2. The defaults in one short list: where the base lives, the language used with them, "opening terminal tabs: on" or "off" (no other detail; leave it out in a cloud or web session), no usage limits, the assistant works only on tasks given to it, the nightly review runs only when asked, no add-ons, one account; any can be changed later: "just tell the agent".
3. List only the steps still left, each from the actual result:
   - "Create the private repository `<repo>` on GitHub": only when `gh api repos/<repo>` did not find it.
   - "Save and upload the files to your repository": `cd <root> && git add -A && git commit -m "Configure home" && git push -u origin HEAD` as one line. If you tried it and it failed, say in one plain sentence that it did not go through, then give that line.
   - "Add the status tags the home uses to track tasks on GitHub": `scripts/labels`; leave it out after `labels: ok`; after "no permission" put the fix first.
   - "Open a session in `<root>` and say "status"" (accept the trust prompt once).
4. Cloud or web session: do the steps yourself and never hand over a command. If one fails, say in one plain sentence what is not done and the one browser action: give the GitHub app access to the repository, then start a new session on it and say "finish the setup".
