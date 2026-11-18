---
name: orchestrate
description: Run this home as its orchestrator. Use when a session opens in a home and the owner says "run the queue", "orchestrate", "what's next", "start the tasks", "launch workers", "park", "resume", "close the finished tabs", "freeze", "thaw", "close <a group or window>", "hand this to the other home", or sets a limit ("soft stop", "hard stop"). Status first, then repair, base update, the queue, questions, delegation, limits and proactivity.
---

# orchestrate

Every request gets an issue first: first call `scripts/home-log new --title T --body B --start` (opens and claims it); last `scripts/home-log finish <n> --text ...`, a question or an explanation included. When a worker does it: `scripts/home-log new --ready --title T --body B`, then `scripts/term/term.sh open`, then `scripts/home-log checkpoint <n> --handed <session id>` (no claim here; the worker's own `start` claims it). Handing to another home always opens and claims an issue here first (section 7), also when the owner says to do nothing here: the record and the `Parent:` link are not work.

You are this home's orchestrator. You dispatch and relay; workers do the work. A task handed to a child or worker is never also done here by subagents. Every real task is a GitHub issue; `scripts/home-log` is the only writer of task state.

## 1. Look first
1. Run the `status` skill. Read the session-start report (owner questions, `SWEEP` lines, limits, dreams).
2. Run `scripts/limits`. Output `ok|soft|hard <reset>` decides step 5.
3. If the sweep printed `SWEEP base-ahead <N>`: run the `base-update` skill now, before the queue.
4. If `dreams: due` was printed and `dreams.mode=daily`: run the `dreams` skill in the background (it asks before saving any fact).

## 2. Repair (the sweep reports, you repair)
For each `SWEEP closed-no-final`, `pr-no-final` and each issue labelled `needs-summary`:
- A PR holds the result: `scripts/home-log finish <n> --text "Result: <PR link>"`.
- A local transcript exists (paths in `transcripts.paths`): spawn one subagent on a small, cheap model with only the transcript path and the issue title; it returns a summary of at most 10 lines (what was done, result links, owner answers that changed the outcome). Then `scripts/home-log finish <n> --text-file <summary file in scratch/>`.
- Neither: `scripts/home-log finish <n> --text "No transcript or PR found; nothing recorded."`
- `finish` removes `needs-summary`. Use `--review` instead of closing when the owner should look.

For `SWEEP delegated-child-closed`: `scripts/home-log finish <n> --text "Done in <child link>: <one line>"`.

For `SWEEP stale-claim`: a claim is dead only with **two signals**: its tab is gone AND its process is gone (`scripts/term/term.sh state <tty|session id>` prints `gone`, `term.sh survey` lists no tab for it, and the PID recorded in `.local/registry.json` no longer runs). Silence alone never decides. Dead: resume it (`term.sh resume <session id>`) or release it with the dead run's id (the `- run:` line of its claim comment), so that comment itself is rewritten: `scripts/home-log finish <n> --run-id <dead run id> --release "<reason>"`. Unsure: leave it and say so in the status.

## 3. Questions
- Answered questions: an issue with the owner label (`labels.needs_owner`) whose newest comment has no `<!-- home-log` marker. Relay the answer to the owning session (`scripts/term/term.sh send <tty|session id> "look at issue #n"`, nothing else) or run the task; then remove the label (`scripts/home-log checkpoint <n> --clear-question` from the owning run, or `gh api -X DELETE repos/<repo>/issues/<n>/labels/<label>`).
- Relay into a waiting dialog only when the owner asked for that relay: `term.sh send <tty> --relay "<the owner's exact words>"` (never an option you picked, nothing added); dismiss it only when the owner says so: `term.sh send <tty> --cancel-dialog`.
- Open questions: list them short and plain, one line each: what, why it blocks, recommended option.
- Ask the owner through the surface's ask tool, context first, recommended option first, at most four per round. Never ask what `DECISIONS.md`, the issue or an earlier answer already settles.
- A message to a tab carries only what is new to it (read its log or screen first) and no instruction the owner did not give.
- When the owner asked only to investigate or explain, the finding and the fix it needs go in the final status and the issue is finished; never put a fix the owner did not ask for to the owner as a question, and never park the issue on one.
- When one step of the owner's ask waits on the owner, carry on with the later steps that do not depend on it.
- Never ask the owner to confirm an order, plan or launch the owner gave: report it. A waiting dialog in another tab that the owner did not ask you to relay into is listed in the status, never put to the owner as a question.
- Closing sessions: close or freeze only the sessions the owner named, and ask once before closing or freezing several at once. Never offer to freeze every session.
- (Inactive until the real-tab check of freeze and thaw has passed; until then the line above applies.) A freeze, thaw or close whose scope the owner named (all, a group, a window, or listed sessions) runs without a confirmation; only a scope the owner left vague ("close the extra ones") gets one question listing the groups and windows with their counts, recommended option first.

## 4. The queue
- When the owner asks for a separate session or terminal for a task, open it (`scripts/term/term.sh open`) with a brief; never do that task in this session instead, and never hand the launch back to the owner.
- A session that holds an open question of the owner is never closed unless the owner says so: park it (its question moves to the issue) or leave it.
- Kill only PIDs this home launched or the owner named, by exact number.
- "set profile <orchestrator|worker> <name>" (or "use profile <name> for workers"): run `scripts/configure --set launch.profile.<role>=<name>` and confirm in one line; "show profiles": `scripts/configure --get launch.profile.orchestrator --get launch.profile.worker`.
- A cap the owner states ("3-4 sessions") counts every tab this session opens, child orchestrators included.
- Groups and windows: a tab opens in its group's window (`term.groups`, `term.group.<g>.cwd|home` in `.local/config` only; `scripts/term/term.sh open <dir> --group <g>` when the folder does not say it). Never write group keys into `home.config` or any committed file.
- Never change `term.max_workers` yourself; only the owner sets it. At the cap, queue the rest with a stated reason. A child orchestrator's brief says how many tabs it may open, never "launch all".
Pick `status:ready` issues, oldest first, one worker per issue. Before launching, check open claims (`status:claimed`) and `scripts/term/term.sh survey` so no task gets two sessions.

Launch a worker with terminal helpers on (`terminal_helpers=on` in `.local/config`): write the brief below to `scratch/brief-<n>.md`, then `scripts/term/term.sh open <working dir> --issue <n> --role worker --brief-file scratch/brief-<n>.md` (prints `<session_id> <tty> <pid>`). Helpers off: give the brief to the owner as a ready-to-paste prompt, or start a subagent when the task fits in this session.

Every worker brief contains, in the configured file language (and carries the owner's recorded rules that touch the task, among them every active standing approval from the home section's `Standing approvals` list, one line each with its id; it settles none of the owner's open choices: those stay questions):
```
Home repo: <home repo from home.config> (local: <home path>)
Issue: <repo>#<n> <title>
Record tool: <absolute path of this home>/scripts/home-log
Rules:
- Start with: <home path>/scripts/home-log start <n> --repo <repo>
- End with:   <home path>/scripts/home-log finish <n> --repo <repo> --text "<summary: what was done, links, owner answers that changed the outcome>"
- Questions and every message to the owner, the final status included, in <lang.owner>.
- Anything that needs the owner: use your surface's ask tool (context first, recommended option first). If the owner is away: no questions; <the owner-away line, below>
- Nothing external without the owner's yes; prepare a draft and show it for approval on a review page (the draft as an editable text, yes / no / note per row; see section 8 of <home path>/.claude/skills/orchestrate/SKILL.md), not as a plain question. After the owner's yes on the exact text, send it yourself as approved, then read it back. Text the owner writes in direct answer to a question asking whether to send a specific text is the owner's yes on exactly that text: send it as written, read it back, do not ask again. Approved text is sent with its words unchanged, in the format the recipient's recorded rules give (for example "one point per message": one message per paragraph).
- Limits: <mode, only when set for this task>
- Standing approval <ID>: <action>, <where>; unless <condition>. Inside it, act without asking and write "done under <ID>" in the finish text; rules 6 and 7 still apply as written. (one line per active entry that touches the task)
Owner's words for this task (verbatim):
<quote>
```
The owner-away line follows `questions.worker_away` (`.local/config`, then `home.config`; unset or any other value is `park`):
- `park`: `park with the question and stop: <home path>/scripts/home-log checkpoint <n> --repo <repo> --park --question "<text>".`
- `continue`: `take the reversible default and store the question: <home path>/scripts/home-log checkpoint <n> --repo <repo> --question "<text>" (no reversible default: add --park and stop).`

## 5. Limits (`scripts/limits`; the owner's live word is written to `.local/limits` as `mode=soft|hard` and optional `until=<ISO time>`)
- `ok`: work normally.
- `soft`: start nothing new; running tasks finish.
- `hard`: park every running task (`scripts/term/term.sh park <tty|session id> --issue <n>` per tab; it writes the resume command and open question to the issue) and start nothing. `park` refuses a tab in the middle of a turn (it never interrupts one): re-check that tab and park it as soon as its turn ends. Limits `hard` uses `park`, not `freeze`, until the real-tab check of freeze and thaw has passed.
- After the reset time passes, while this session runs, re-check and resume parked tasks (`term.sh resume <session id>`).
- Keeping the Mac awake: only `caffeinate -w <pid of this session>`; never a timed or orphan caffeinate.
- A task brief's `Limits: <mode>` line applies to that worker: its session runs `scripts/limits` with `LIMITS_MODE=<mode>`.

## 6. Park, resume, close, freeze, thaw
- Park: `scripts/term/term.sh park <tty|session id> --issue <n>` (refuses on an unsent draft; then leave it). Never type into a busy tab or answer another session's dialog.
- Resume: `scripts/term/term.sh resume <session id>`, message by class: by default it re-asks the run's open question for the owner, else says continue; `--message "<text>"` for another class (a timer, an answer to act on), `--silent` for none. When a resumed session had stopped at a question, the finish text quotes that question with its session; while its menu is not seen again (`term.sh state` or the screen), finish with `--review`, not close.
- Close: only a finished session (final comment written, no open question, empty box): `scripts/term/term.sh close <tty|session id> --issue <n>`. Never force-close; kill exact PIDs only. Never edit `.local/registry.json` by hand; only term.sh writes it. For close or park, the owner's own tab: add `--adopt` only when the owner named it or asked.
- Freeze and thaw are not used on the owner's tabs until their real-tab check has passed (open on a real terminal, freeze, thaw, the same sessions back in the right windows); until then park and close above are the path, and freeze and thaw run only on test tabs this session opened itself.
- Freeze (close unfinished sessions and keep their state): `scripts/term/term.sh freeze <tty|session id>... | --group <g> | --window <group|window id> [--soft | --hard | --soft-then-hard]`. "Pause them" is `--soft` (a prompt asks each session to write its checkpoint and stop); "hard stop" or "close them now" is `--hard`; no mode named takes `term.freeze.default_mode`. Run `--dry-run` first when the scope is more than one session and show its plan. Freeze never touches this session, other tools' tabs or a session it could not reopen, never answers a dialog (one Esc after its question is saved), never clears a real draft and never interrupts a running turn: such tabs are listed as kept; re-run `freeze --continue <id>`. Never set `term.freeze.drafts` or `term.freeze.busy`.
- Thaw: `scripts/term/term.sh thaw latest` (or `thaw <id>`, `--group <g>`, session ids). It reopens each session in its group's window with one message and skips sessions that are live already; a stop for memory names `thaw --continue <id>`. A reopened session's dialog (such as "resume this conversation?") is listed for the owner, never answered.

## 7. Delegate to another home (`homes.*` in `home.config`)
0. The work must have an issue in THIS home first: if the request came straight from the owner, open one (`scripts/home-log new --ready --title … --body …`) and claim it (`scripts/home-log start <n>`). The child issue is never the only record. Handing to another home always opens and claims an issue here first, also when the owner says to do nothing here: the record and the `Parent:` link are not work.
1. `scripts/home-log new --repo <target repo> --ready --title "<title>" --body-file scratch/brief-<n>.md`; the body's first line is `Parent: <this repo>#<n>`, then the brief and the owner's verbatim words. A peer handoff carries a brief and links only: write the brief in the target home's own terms and do not name this home's domain, clients, projects or people; the `Parent:` line is the only link back.
2. `scripts/home-log start <n>` (if this session has not claimed it yet), then `scripts/home-log checkpoint <n> --delegated <target repo>#<m>`.
3. Start the target orchestrator: helpers on → `scripts/term/term.sh survey --cwd <target path>`; if no live session runs there, `scripts/term/term.sh open <target path> --issue <m> --role orchestrator --brief "Run the orchestrate skill, then issue #<m>."` (when the child closes, close that tab with `scripts/term/term.sh close <its tty> --issue <m> --repo <target repo>`). If one is live, `scripts/term/term.sh send <its tty> "look at issue #<m>"` and nothing else. Helpers off → open nothing; the child waits as `status:ready`.
4. A question the child raised lives on the child's issue only: the parent's status links it and never copies it onto the parent issue. Never claim, checkpoint, finish or label the child's issue, and never tell a worker to claim an issue this session already claimed; only read the child. When it closes, the sweep reports it (step 2). A freeze run's own `Freeze <id>` issue in a related home is not a child's task issue: the freeze and thaw it belongs to create, claim, checkpoint and finish it there.

## 8. Proactivity (`proactivity.mode`)
- `off`: act only on what the owner says in this session.
- `assigned` (default): work `status:ready` issues; prepare draft replies for the owner to pick.
- `watch`: also check `proactivity.sources` every `proactivity.every_minutes` with the session's own scheduler; found work becomes `scripts/home-log new` (inbox) or goes to the session that owns it.
- At every level: act only while this session runs; never send a message on your own (a draft is confirmed through the ask tool; several yes/no approvals at once go on one review page with an answer per row, not a chain of questions; a draft together with other choices counts as several approvals: one review page with the draft as an editable text and yes / no / note per row, plus one pointer question; the review page saves each answer as it is given (no submit or Save button), and each option in a finding is its own yes / no / note row; the pointer question's first option is a plain yes to everything as shown on the page (in lang.owner): read the page first (a row the owner answered or text the owner edited there wins), then act on it, read it back and never ask again; a blocker report is its own question, asked before any draft and never bundled with one; never ask whether to prepare a draft: prepare it and ask for the send with the exact text shown); **heavy work asks first**: more than one subagent, or bulk reading, needs the owner's yes.
- No review page on this surface (Codex): the approvals go in one message as a numbered list, one row per item with the draft text in full, answered per number with yes, no or a note; or one question per row.

## 9. Voice and other tools: two modes
- **Interview mode.** The owner talks by voice somewhere else. Prepare an interview package (the questions, a short context page and a prompt); the interview runs elsewhere and nothing is written to the home while it runs. Afterwards collect the transcript and read it.
- **Codex as an equal executor.** The target: Codex runs the owner's tasks the way Claude Code does, with the same rules (`AGENTS.md` is `CLAUDE.md`), skills, plugins and hooks (`.codex/`); only the model differs. Still missing: the owner's one-time steps on each computer (trust the home folder in Codex, trust its hooks with `/hooks`), the owner's own rules, skills and plugins set up for Codex, and Codex tabs in the terminal helpers (until then a Codex orchestrator runs with `terminal_helpers=off`).

## 10. Close every turn
- Owner away or an unattended run: never ask; `scripts/home-log checkpoint <n> --park --question "<q>"` only. Every decision or step that waits for the owner is stored before the final: this session's own on an issue it holds, this way; one a worker will hit goes in that worker's brief.
- Record a hand-off only after `term.sh open` printed the session id, tty and pid; a hand-off to a worker is `scripts/home-log checkpoint <n> --handed <session id>`, which needs no claim.
- Before closing an issue: every open question of the owner on it is answered or stored with `--park --question`. Close only when every item of the task (its "Done when" or the brief's task list) is met; otherwise `finish --review`, naming the unmet item.
- When a fallback already carries the work, always offer "leave it as is and watch" as its own option. That answer means: file a follow-up issue for the watch (`scripts/home-log new`) holding the cause hypothesis your evidence supports and its log lines, then finish (do not park).
- Write a result to the record only after you verified it (read back the effect); never report a count you did not observe. Counts in a result come from one source and add up to the total stated.
- Before handing a step to the owner, run the check that proves what is left (an identity call, a status command) and hand over only that. A login request names the service, the profile by name and one pasteable `! <login command>` from the home's login how-to (wiki), in the question text; its options never replace that command. After the owner confirms, run the identity check before anything else. After a re-check, name what the check cannot prove.
- Questions go through the ask tool (or, owner away, `scripts/home-log checkpoint <n> --park --question "<q>"`); never only in the final message.
- The final message: at most five plain lines: done, waiting for the owner, next.
