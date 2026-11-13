---
name: configure
description: Make this repo the user's own home from the base. Use when someone says "configure", "set up my home", "make a home from this base", "onboard me", after cloning the base, "finish the setup", or with an answers file ("configure --answers <file>") for an unattended setup.
---

# configure

One code path: `scripts/configure --answers <file> [--labels]`. Interactive mode only collects the answers. `templates/answers.example` lists every key with an example.

## Order of work
1. The repo root: `git rev-parse --show-toplevel`; work only in that folder (`<root>` below): run the scripts there, write `.local/answers` there, never create files or a second home in a subfolder.
2. The session checks below.
3. The GitHub login, on its own: `gh api user --jq .login`. If it fails, ask the repository question without a recommendation and say nothing about GitHub now; GitHub problems are reported only in Finish.
4. Ask. Then write the answers and run the script.

Configure opens no issue and does not use `scripts/home-log`: the home has no repository yet. Never mention an issue during setup.

## Where is this session?
Every check is its own command; never join two.
- First command, alone: `echo "${CLAUDE_CODE_REMOTE:-}"`. If it prints anything, or the person says they have no terminal or work only in the browser, this is a cloud or web session: `terminal_helpers=off`, no further checks, never mention terminals, tabs or this machine, and do the remaining steps yourself.
- Only if it printed nothing: `uname -s` alone. Not `Darwin`: `terminal_helpers=off`, no application check, never mention iTerm2. `Darwin`: `echo "${TERM_PROGRAM:-}"`; `iTerm.app` gives `on` (the script's device check keeps `off` if it fails), anything else `off`. Never decide from an installed application. Do not ask.
- If the person asks about Codex: in a cloud or web session say "the home works with Codex as-is when the same repository is opened with Codex, because Codex reads the same rules file and the same skills; nothing to install here". On a computer run `command -v codex` and answer from it: the home works with Codex because `AGENTS.md` is the same file as `CLAUDE.md` and the skills folder is shared.

## Asking: two rounds
Use the surface's ask tool, in the language the person writes in, in plain everyday words. Never show a key name or the words labels, hooks, plugins, dreams, proactivity, limits, config, MCP, worker, orchestrator. Round one: owner, purpose, never-allowed, own rules. Round two: repository name, file language, team board. Skip anything already in `.local/answers` or in answers the person pasted. Give examples only for the purpose, and only from the person's own words; never name a board product the person did not name.
- A round is one numbered free-text list, each recommendation inside its own question ("... (recommended: English)"). Use an options list only for a round with a single question, never one that mixes answers to different questions.
- No ask tool (Codex): finish every check first. The numbered questions are the final message of the turn: no progress or status message before or after them, and never "the questions above". Ask round two the same way after the reply.

| Ask (plain words) | Key | How |
|---|---|---|
| "Who owns this home? Your name, or the names of the people who share it." | `owner.names` | Write the names exactly as typed, in their own script; never transliterate. Never pre-fill from the OS user, git identity or GitHub login. |
| "What is this home for? One line." | `home.domain` | Free text. |
| "What must never be put in it?" | `home.boundary` | Free text, no options, no example answers. |
| "Any rules of your own the assistant should always follow here? None is fine." | `home.rules` | Free text, no options, no example answers. Record every rule the answer mentions, in the person's meaning, even one they think is already covered; never judge one redundant, never invent one. Zero is valid. |
| "What should the GitHub repository for this home be called? If you have already created one, give its name." | `repo` | Recommend `<GitHub login>/<short-name>-home`; it must not be the base. Note whether the person says it is created, not created, or asks you to create it. |
| "Which language should the files be written in?" | `lang.files` | Recommend English. |
| "Do you use a team board for tasks? Which one?" | `tracker.board` | `none` or the board's name in lower case. |

## Defaults, set silently
- `base.url`: the URL of the `base` remote if it exists, otherwise of `origin` (the base they cloned).
- `lang.owner`: the language the person writes in. `terminal_helpers`: from the checks above.
- `tracker.board_write=ask-first` only when a board is named; `labels.needs_owner=needs-owner`.
- `limits.mode=none`, `proactivity.mode=assigned`, `dreams.mode=manual`, `plugins=` (empty), `accounts.multi=no`, launch keys empty, no related homes.
Ask about any of these only when the person brings the topic up.

## Run
Write every answer and default as `key=value` lines to `<root>/.local/answers` (gitignored; repeatable keys one line each). If the person asked you to create the repository, `gh api user` worked and `gh api repos/<repo>` found nothing, run `gh repo create <repo> --private` first. Then run `scripts/configure --answers .local/answers --labels` from `<root>` (on Codex, ask for elevated permission: it changes the repository's git settings). It removes the base's own files and points `origin` at the new repo; it never pushes.
- Exit 2: ask for exactly the keys it lists (or report them when unattended) and run again.
- Exit 3: the repo is not ready or a write or git step failed; the line names it. Fix that and run again.
- Exit 5: the files are written, but this session may not change the repository's git settings. Do not retry; go to Finish.
- Exit 4: the files are written, the status tags are not. State only the printed cause, with its fix, in one sentence; never a second cause or a conditional fix. "was not found on GitHub", or the person said the repository is not created (their word wins): the repository does not exist yet, which is the normal first run. "no permission to manage labels": the fix for this surface (on a computer `gh auth refresh -s repo`; in a cloud or web session the browser action from Finish); do not run `scripts/labels` again in this session. Anything else: what GitHub refused. Never say the tags exist.

## Finish
In the person's language and plain words, without key names, file names or session tooling.
1. Every key from the ask table has an answer; the rest may be defaults.
2. The defaults as bullet lines, one per default: "Updates to this setup come from: <base.url>", the language used with them, "opening terminal tabs: on" or "off" (left out in a cloud or web session), no usage limits, the assistant works only on tasks given to it, the nightly review runs only when asked, no add-ons, one account. Then: any can be changed later, "just tell the agent".
3. The repository in one sentence when needed: "it was created as private" after you created it; "a repository with this name already exists on your account; I used it" when it was found although the person said they had not created it.
4. After exit 3 or 5: say in plain words what is saved on this computer and what is not yet set up, with no file names.
5. Only the steps still left, each from the actual result, in this order:
   - After exit 3 or 5: `cd <root> && scripts/configure --answers .local/answers`, run from their own terminal (after exit 3, once the named problem is fixed).
   - "Create the private repository `<repo>` on GitHub": when `gh api repos/<repo>` found nothing or the person said it is not created; after a failed `gh repo create`, with its reason.
   - "Save and upload the files to your repository": `cd <root> && git add -A && git commit -m "Configure home" && git push -u origin HEAD` as one line. If you ran it and only the upload failed, say "the files are saved on this computer but not uploaded yet", give only `cd <root> && git push -u origin HEAD`, name no cause, and never say "commit".
   - "Add the status tags the home uses to track tasks on GitHub": `scripts/labels`; left out after `labels: ok`; after "no permission" the fix first.
   - "Open a session in `<root>` and say "status"" (accept the trust prompt once).
6. Cloud or web session: do the steps yourself and never hand over a command. For each failed step one short sentence of what is not done ("the files are saved in this session but not uploaded yet"; "the status tags are not added yet"), with no cause. If the upload failed, the one action is: create the repository if it is missing, give the GitHub app access to it, then come back to this session and say "finish the setup". Then print the answers as a short block to paste if this session is gone (open the base again, say "set it up", paste it). Nothing about network or session settings.

## "Finish the setup"
- `home.config` exists in `<root>`: run only what is pending: upload the files if the remote is behind, then `scripts/labels`; report what is now done in one or two lines.
- `scripts/configure` is missing (an empty repository): nothing can run here. Say the setup finishes in the session where it started; if that session is gone, open the base again, say "set it up" and paste the answers block.
- Otherwise (a base clone without `home.config`): run from `.local/answers` if it exists, else ask the two rounds; then Run and Finish.
