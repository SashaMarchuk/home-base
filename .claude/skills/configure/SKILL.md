---
name: configure
description: Make this repo the user's own home from the base. Use when someone says "configure", "set up my home", "make a home from this base", "onboard me", after cloning the base, "finish the setup", or with an answers file ("configure --answers <file>") for an unattended setup.
---

# configure

One code path: `scripts/configure --answers <file> [--labels]`; interactive mode only collects the answers (`templates/answers.example` lists every key). No issue, no `scripts/home-log`, never a mention of an issue: the home has no repository yet.

**Every turn ends in exactly one of two ways: the numbered questions, or the result with the steps still left.** In a question turn the questions are the only text, shown once: no greeting, status or "a few questions first" before, nothing after. With an ask tool, the ask call is all the person sees; without one (Codex), do every check first, post no message before, between or after the commands, and make the numbered questions the turn's single message, never "waiting for your answers" or a form. Ask only what is not answered yet (conversation, `.local/answers`, pasted answers); no second round when the first reply settles everything. Write no file but `<root>/.local/answers`; the summary and steps go in the message in full, never naming or linking a file or this skill, never quoting these instructions.

## Order of work
1. `git rev-parse --show-toplevel` (`<root>`); work only there.
2. The session checks, then the base address: `git remote get-url base || git remote get-url origin`.
3. The GitHub login, alone: `gh api user --jq .login`. GitHub problems wait for Finish.
4. Ask, then Run.

## Session checks
One command each, never joined, awaited in turn:
1. `echo "${CLAUDE_CODE_REMOTE:-}"`. Prints anything, or the person works only in a browser: cloud or web session; `terminal_helpers=off`, stop, never mention terminals, tabs or this machine.
2. `uname -s`. Not `Darwin`: `terminal_helpers=off`, stop, never mention iTerm2 or Cmd+Space.
3. `echo "${TERM_PROGRAM:-}"`: `iTerm.app` gives `on`, else `off`; a terminal app the person names wins (not iTerm2: `off`). Never from an installed application; never ask.

Asked about Codex: "Yes: nothing has to be added to the home. Open the same repository with Codex (the app or command line, which must be installed where you use it) and it reads the same rules file and skills." On a computer where `command -v codex` finds nothing, add "Codex is not installed on this computer yet"; in a cloud session never imply it is present.

## Questions
Plain everyday words in the person's language, never a key name or labels, hooks, plugins, dreams, proactivity, limits, config, MCP, worker, orchestrator. Round one: the first four rows; round two: the rest. A round is one numbered free-text list, each recommendation inside its question ("... (recommended: English)"); options only for a single-question round. Examples only for the purpose, from the person's own words; no board product they did not name.

| Ask (plain words) | Key | How |
|---|---|---|
| "Who owns this home? Your name, or the names of the people who share it." | `owner.names` | Exactly as typed, in their own script; never transliterated or taken from the OS user, git identity or GitHub login. |
| "What is this home for? One line." | `home.domain` | Free text. |
| "What must never be put in it?" | `home.boundary` | Free text, no options or example answers. |
| "Any rules of your own the assistant should always follow here? None is fine." | `home.rules` | Same. One line per separate rule, even when given in one sentence; every rule mentioned, even one they think is covered, none invented. Zero is valid. |
| "What should the GitHub repository for this home be called, and does it already exist?" | `repo` | Recommend `<login>/<word>-home`, `<word>` one word from the purpose (none fits: `my`); before asking, `gh api repos/<login>/<word>-home --jq .full_name`, alone: found, add "which already exists on your account", else "I will tell you how to create it if it does not exist". No login: none. Never the base. Note whether it exists or you should create it; silence means not created. |
| "Which language should the files be written in?" | `lang.files` | Recommend English. A two-letter code (`en`, `es`). |
| "Do you use a team board for tasks? Which one?" | `tracker.board` | Recommend "No board (recommended for one person)". `none` or the board's name, lower case. |

`home.domain`, `home.boundary` and `home.rules` are written in the file language, translated faithfully (nothing added or dropped); only names keep the person's own words.

## Defaults, set silently
`base.url=` from step 2; `lang.owner=` the code of the person's language; `terminal_helpers=` from the checks; `launch.command=codex` in a Codex session, else `claude`; `tracker.backend=github`; `tracker.board_write=ask-first` only when a board is named; `labels.needs_owner=needs-owner`; `limits.mode=none`; `proactivity.mode=assigned`; `dreams.mode=manual`; `plugins=` (empty); `accounts.multi=no`. Never asked unless raised.
The launch profiles are not asked; the owner sets them later by saying "set profile worker <name>" (or orchestrator).

## Run
Write every answer and default as `key=value` lines (repeatable keys one per line) to `<root>/.local/answers` without checking first. Asked to create the repository: `gh repo create <repo> --private` only when `gh api repos/<repo>` finds nothing; it decides nothing else. Then from `<root>`, once, as is: `scripts/configure --answers .local/answers --labels` (safe to run again).
- Exit 0 or 4 without a `pending:` line: run `git add -A && git commit -m "Configure home"`, then `git push -u origin HEAD`, yourself; only a failed step goes into Finish. With one: never push or retry.
- Exit 2: ask for exactly the keys listed (unattended: report them), run again. Exit 3: fix the named problem, run again. Exit 5: no retry; go to Finish.
- Exit 4: the status tags are not added; the last line ends with the line that adds them (after a `pending:` line, also links and uploads).

## Finish
Once every asked key is answered; the person's language, plain words, no key or file names. Quoted sentences are fixed: translate faithfully, never shorten.
- **Summary**, as bullets:
  - "Improvements to this setup can be pulled later from: <base.url>"
  - "Language: <files language> for files, <their language> with you"
  - On a computer: "When a task needs its own window, the assistant opens a new terminal tab for it" when on, "The assistant does not open terminal tabs for you" when off.
  - A board: "Team board: <name>; the assistant reads it and asks before changing anything there".
  - Then: "Everything else is off or manual until you ask: no usage limits, no work on its own, no nightly review of past work, no add-ons, one account. To change any of it, just tell the assistant."
- **When needed**:
  - Exit 4: only the cause, once, never its fix, another cause or that the tags exist: `gh api user` could not connect: "I could not reach GitHub from this session, so the repository is not created and the status tags are not added yet"; "was not found", or the person said it does not exist (their word wins): "the repository does not exist yet"; "no permission": "the status tags are not added yet: this GitHub login may not manage them in `<repo>`"; else what GitHub refused.
  - "it was created as private" after you created it; "a repository with this name already exists on your account; I used it" only when the upload or a tag write succeeded although the person said it does not exist.
  - After exit 5: "Your answers and files are saved on this computer; one last step that links this folder to your own GitHub repository must be run by you." After exit 3: what is saved and what not.
- **Steps left, on a computer**, numbered, each command starting with `cd <root> &&`, after once: on Darwin "To run a line: open Terminal (Cmd+Space, type Terminal, Enter), paste the line, press Enter." (in iTerm2: "open iTerm (Cmd+Space, type iTerm, Enter)"); otherwise "To run a line: open a terminal, paste the line, press Enter."
  - After exit 5, the printed line; after exit 3 once fixed, `cd <root> && scripts/configure --answers .local/answers`.
  - "Create the repository: on github.com/new choose owner <login>, name <name>, Private, and add no README.": when it was not found, said not to exist, or GitHub could not be reached; after a failed `gh repo create`, with its reason.
  - Upload not done: "Save and upload the files to your repository": `cd <root> && git add -A && git commit -m "Configure home" && git push -u origin HEAD`. With a `pending:` line: the pending line, ` && `, then that command without its `cd <root> && `, and "this session may not change the repository's git settings, so this one line, run in a terminal in `<root>`, finishes it and uploads the files"; after exit 4 the printed line already holds all of it and the tags: one step, no tags step. Only the push failed: "the files are saved on this computer but not uploaded yet" and only `cd <root> && git push -u origin HEAD`, no cause, never "commit".
  - Tags missing: "Add the status tags the home uses to track tasks on GitHub": the line exit 4 ended with, else `cd <root> && scripts/labels`; unless it holds `gh auth refresh`, add "if it says this login cannot manage the tags, run `gh auth refresh -s repo` and repeat the line".
  - Always last: "Start working: run `cd <root> && <tool>`, accept the question whether you trust this folder once, then type: status", `<tool>` only this session's tool (`codex` or `claude`).
- **Cloud or web session**: do every step yourself, hand over no command; nothing about network or session settings.
  - Per failed step, what is not done ("the files are saved in this session but not uploaded yet"; "the status tags are not added yet"); after a tag "no permission", add "because this session may not change the repository's settings; giving the GitHub app read and write access to `<repo>` fixes it".
  - Upload failed: the one action "create the private repository `<repo>` on GitHub if it is not there yet; on github.com/settings/installations open Claude, Configure, and add `<repo>` with read and write access; then come back to this session and say 'finish the setup'" (first clause dropped only after an upload or tag write succeeded or the person said it exists), then the answers as plain labelled lines in the person's language (Owner, Purpose, Never store, My rules, Repository, File language, Team board), never `key=value`, with "if this session is gone, open a new session on <base.url>, say 'set it up' and paste this".
  - Always last: "To start working, open a new session on `<repo>` the way you opened this one, and type: status".

## "Finish the setup"
- `home.config` exists: upload if the remote is behind and `origin` is the home's repo (else the pending line as in Finish), then `scripts/labels`; say briefly what is done, then the start step.
- No `scripts/configure` (an empty repository): run nothing; it finishes in the first session or, if gone, a new session on the base address with "set it up" and the pasted answers.
- Otherwise: `.local/answers` if it exists, else ask; then Run and Finish.
