---
name: configure
description: Make this repo the user's own home from the base. Use when someone says "configure", "set up my home", "make a home from this base", "onboard me", after cloning the base, "finish the setup", or with an answers file ("configure --answers <file>") for an unattended setup.
---

# configure

One code path: `scripts/configure --answers <file> [--labels]`. Interactive mode only collects the answers. `templates/answers.example` lists every key with an example.

**Every turn ends in exactly one of two ways: the numbered questions (and nothing after them), or the result of `scripts/configure` with the steps still left.** Never end a turn with a status line, and never post questions in an earlier message of the turn. Do all reading (including `templates/answers.example`, if needed) before the questions. Ask only what the person has not already answered; when the first reply settles everything, run the script without a second round.

## Order of work
1. The repo root: `git rev-parse --show-toplevel` (`<root>` below); run the scripts and write `.local/answers` only there, never in a subfolder.
2. The session checks below, then the base address: `git remote get-url base || git remote get-url origin`.
3. The GitHub login, alone: `gh api user --jq .login`. If it fails, ask the repository question without a recommendation; GitHub problems are reported only in Finish.
4. Ask. Then write the answers and run the script.

Configure opens no issue, does not use `scripts/home-log` and never mentions an issue: the home has no repository yet.

## Where is this session?
Every check is its own command; never join two.
- First, alone: `echo "${CLAUDE_CODE_REMOTE:-}"`. If it prints anything, or the person has no terminal or works only in the browser, this is a cloud or web session: `terminal_helpers=off`, no further checks, never mention terminals, tabs or this machine; do the remaining steps yourself.
- Only if it printed nothing: `uname -s` alone. Not `Darwin`: `terminal_helpers=off`, no application check, never mention iTerm2. `Darwin`: `echo "${TERM_PROGRAM:-}"`; `iTerm.app` gives `on` (the script's device check keeps `off` if it fails), anything else `off`. If the person names the terminal app they use, their word wins: anything but iTerm2 gives `off`. Never decide from an installed application. Do not ask.
- Asked about Codex: "the home works with Codex as-is when the same repository is opened with Codex: it reads the same rules file and the same skills; nothing to install" (on a computer, after `command -v codex`).

## Interactive: two rounds
- **No ask tool (Codex): your LAST message of the turn is the numbered questions and nothing else. Do every check before it. Never write "waiting for your answers" or refer to a form.** Round two goes the same way after the reply.
- Otherwise use the surface's ask tool. Either way: the person's language, plain everyday words, never a key name or the words labels, hooks, plugins, dreams, proactivity, limits, config, MCP, worker, orchestrator. Round one: owner, purpose, never-allowed, own rules. Round two: repository name, file language, team board. Skip anything already in `.local/answers` or pasted answers. Examples only for the purpose, only from the person's own words; never name a board product they did not name.
- A round is one numbered free-text list, each recommendation inside its own question ("... (recommended: English)"). Use an options list only for a round with a single question.

| Ask (plain words) | Key | How |
|---|---|---|
| "Who owns this home? Your name, or the names of the people who share it." | `owner.names` | Exactly as typed, in their own script; never transliterate or pre-fill from the OS user, git identity or GitHub login. |
| "What is this home for? One line." | `home.domain` | Free text. |
| "What must never be put in it?" | `home.boundary` | Free text, no options, no example answers. |
| "Any rules of your own the assistant should always follow here? None is fine." | `home.rules` | Free text, no options, no example answers. Record every rule mentioned, in the person's meaning, even one they think is covered; never judge one redundant or invent one. Zero is valid. |
| "What should the GitHub repository for this home be called? If you have already created one, give its name." | `repo` | Recommend `<login>/<short-name>-home`, where `<short-name>` is one word from the purpose answer; when no word fits, `<login>/home`. Never the base. Note whether the person says it is created, not created, or asks you to create it. |
| "Which language should the files be written in?" | `lang.files` | Recommend English. Written as a two-letter code (`en`, `es`). |
| "Do you use a team board for tasks? Which one?" | `tracker.board` | `none` or the board's name, lower case. |

## Defaults, set silently
`base.url=` the address from Order of work step 2; `lang.owner=` the two-letter code of the language the person writes in; `terminal_helpers=` from the checks; `tracker.backend=github`; `tracker.board_write=ask-first` only when a board is named; `labels.needs_owner=needs-owner`; `limits.mode=none`; `proactivity.mode=assigned`; `dreams.mode=manual`; `plugins=` (empty); `accounts.multi=no`. Ask about any of these only when the person brings the topic up.

## Run
Write every answer and default as `key=value` lines to `<root>/.local/answers` (repeatable keys one line each) without checking first; the script adds `.gitignore` with `.local/` itself. If the person asked you to create the repository, `gh api user` worked and `gh api repos/<repo>` found nothing, run `gh repo create <repo> --private` first. Then run `scripts/configure --answers .local/answers --labels` from `<root>`, once, as is; it removes the base's own files, points `origin` at the new repo and never pushes.
- A `pending: <line>` in the output: this session may not change the repository's git settings; everything else is done. `origin` is still the base: never push or retry; the line goes into the upload step of Finish.
- Exit 2: ask for exactly the keys listed (or report them when unattended), run again.
- Exit 3: the named problem; fix it and run again.
- Exit 5: git refused a step unexpectedly; the last line gives the full line to run. Do not retry; go to Finish.
- Exit 4: the files are written, the status tags are not. Say only the printed cause in one sentence, never its fix (that is the Finish tags step) or a second cause: "was not found on GitHub", or the person said it is not created (their word wins): the repository does not exist yet, the normal first run; "no permission to manage labels": "the status tags are not added yet: this GitHub login may not manage them in `<repo>`", and do not run `scripts/labels` again here; else what GitHub refused. Never say the tags exist.

## Finish
In the person's language and plain words, without key names, file names or session tooling, once every asked key has an answer. The quoted sentences are fixed: translate them faithfully, never shorten them.
1. Three bullets: "Improvements to this setup can be pulled later from: <base.url>"; "Language: <files language> for files, <their language> with you"; "Opening terminal tabs for you: on" (or "off"; left out in a cloud or web session). When a board is named: "Team board: <name>; the assistant reads it and asks before changing anything there." Then: "Everything else is off or manual until you ask: no usage limits, no work on its own, no nightly review of past work, no add-ons, one account. To change any of it, just tell the assistant."
2. The repository, in one sentence when needed: "it was created as private" after you created it; "a repository with this name already exists on your account; I used it" only when the upload or a tag write to it succeeded although the person said it was not created.
3. After exit 5: "Your answers and files are saved on this computer; one last step that links this folder to your own GitHub repository must be run by you." After exit 3: what is saved and what is not, in plain words.
4. A numbered list, one step per line, only the steps still left per the actual result, each command starting with `cd <root> &&`. Before it, once: "To run a line: open Terminal (Cmd+Space, type Terminal, Enter), paste the line, press Enter." (on macOS; elsewhere "open a terminal").
   - After exit 5: the printed rerun line. After exit 3, once the named problem is fixed: `cd <root> && scripts/configure --answers .local/answers`.
   - "Create the repository: on github.com/new choose owner <login>, name <name>, Private, and add no README.": when it was not found or the person said it is not created; after a failed `gh repo create`, with its reason.
   - "Save and upload the files to your repository": `cd <root> && git add -A && git commit -m "Configure home" && git push -u origin HEAD`. With a `pending:` line, one line instead: the pending line, then ` && git add -A && git commit -m "Configure home" && git push -u origin HEAD`, with "this session may not change the repository's git settings, so this one line, run in a terminal in `<root>`, finishes it and uploads the files". If only your push failed: "the files are saved on this computer but not uploaded yet" and only `cd <root> && git push -u origin HEAD`, no cause, never "commit".
   - "Add the status tags the home uses to track tasks on GitHub": `cd <root> && scripts/labels`; after "no permission" `gh auth refresh -s repo && cd <root> && scripts/labels`; left out after `labels: ok`.
   - "Start working: in a terminal run `cd <root> && claude` (or `codex`), accept the question whether you trust this folder once, then type: status".
5. Cloud or web session: do the steps yourself, never hand over a command. Per failed step one sentence of what is not done ("the files are saved in this session but not uploaded yet"; "the status tags are not added yet"); after a tag "no permission", add "because this session may not change the repository's settings; giving the GitHub app read and write access to `<repo>` fixes it". If the upload failed, the one action: "create the private repository `<repo>` on GitHub if it is not there yet; on github.com/settings/installations open Claude, Configure, and add `<repo>` with read and write access; then come back to this session and say 'finish the setup'". Then the answers as a short block, with "if this session is gone, open a new session on <base.url>, say 'set it up' and paste this". Nothing about network or session settings.

## "Finish the setup"
- `home.config` exists in `<root>`: upload the files if the remote is behind and `origin` is the home's repo (otherwise hand over the pending line as in Finish), then `scripts/labels`; report what is now done in one or two lines.
- `scripts/configure` is missing (an empty repository): run nothing; the setup finishes in the session where it started, or, if it is gone, in a new session on the base address with "set it up" and the pasted answers block.
- Otherwise (a base clone without `home.config`): use `.local/answers` if it exists, else ask; then Run and Finish.
