---
name: orchestrate
description: Run this home as its orchestrator. Use when a session opens in a home and the owner says "run the queue", "orchestrate", "what's next", "start the tasks", "launch workers", "park", "resume", "close the finished tabs", "hand this to the other home", or sets a limit ("soft stop", "hard stop"). Status first, then repair, base update, the queue, questions, delegation, limits and proactivity.
---

# orchestrate

Every request gets an issue first: `scripts/home-log new --title ... --body ...`, then `scripts/home-log start <n>` only when this session does the work itself (when a worker does it, open it with `--ready` and leave the claim to the worker's own `start`); then work.

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
- Never ask him to confirm an order, plan or launch he gave: report it. A waiting dialog in another tab that he did not ask you to relay into is listed in the status, never put to him as a question.

## 4. The queue
- When the owner asks for a separate session or terminal for a task, open it (`scripts/term/term.sh open`) with a brief; never do that task in this session instead, and never hand the launch back to him.
- A session that holds an open question of the owner is never closed unless he says so: park it (its question moves to the issue) or leave it.
- Kill only PIDs this home launched or the owner named, by exact number.
- "set profile <orchestrator|worker> <name>" (or "use profile <name> for workers"): run `scripts/configure --set launch.profile.<role>=<name>` and confirm in one line; "show profiles": `scripts/configure --get launch.profile.orchestrator --get launch.profile.worker`.
- A cap the owner states ("3-4 sessions") counts every tab this session opens, child orchestrators included.
Pick `status:ready` issues, oldest first, one worker per issue. Before launching, check open claims (`status:claimed`) and `scripts/term/term.sh survey` so no task gets two sessions.

Launch a worker with terminal helpers on (`terminal_helpers=on` in `.local/config`): write the brief below to `scratch/brief-<n>.md`, then `scripts/term/term.sh open <working dir> --issue <n> --role worker --brief-file scratch/brief-<n>.md` (prints `<session_id> <tty> <pid>`). Helpers off: give the brief to the owner as a ready-to-paste prompt, or start a subagent when the task fits in this session.

Every worker brief contains, in the configured file language (and carries the owner's recorded rules that touch the task; it settles none of the owner's open choices: those stay questions):
```
Home repo: <home repo from home.config> (local: <home path>)
Issue: <repo>#<n> <title>
Record tool: <absolute path of this home>/scripts/home-log
Rules:
- Start with: <home path>/scripts/home-log start <n> --repo <repo>
- End with:   <home path>/scripts/home-log finish <n> --repo <repo> --text "<summary: what was done, links, owner answers that changed the outcome>"
- Anything that needs the owner: use your surface's ask tool (context first, recommended option first). If the owner is away: no questions; take the reversible default and store the question: <home path>/scripts/home-log checkpoint <n> --repo <repo> --question "<text>".
- Nothing external without the owner's yes; prepare a draft. After his yes on the exact text, send it yourself as approved, then read it back.
- Limits: <mode, only when set for this task>
Owner's words for this task (verbatim):
<quote>
```

## 5. Limits (`scripts/limits`; the owner's live word is written to `.local/limits` as `mode=soft|hard` and optional `until=<ISO time>`)
- `ok`: work normally.
- `soft`: start nothing new; running tasks finish.
- `hard`: park every running task (`scripts/term/term.sh park <tty|session id> --issue <n>` per tab; it writes the resume command and open question to the issue) and start nothing. `park` refuses a tab in the middle of a turn (it never interrupts one): re-check that tab and park it as soon as its turn ends.
- After the reset time passes, while this session runs, re-check and resume parked tasks (`term.sh resume <session id>`).
- Keeping the Mac awake: only `caffeinate -w <pid of this session>`; never a timed or orphan caffeinate.
- A task brief's `Limits: <mode>` line applies to that worker: its session runs `scripts/limits` with `LIMITS_MODE=<mode>`.

## 6. Park, resume, close
- Park: `scripts/term/term.sh park <tty|session id> --issue <n>` (refuses on an unsent draft; then leave it). Never type into a busy tab or answer another session's dialog.
- Resume: `scripts/term/term.sh resume <session id>`, message by class: by default it re-asks the run's open question for the owner, else says continue; `--message "<text>"` for another class (a timer, an answer to act on), `--silent` for none.
- Close: only a finished session (final comment written, no open question, empty box): `scripts/term/term.sh close <tty|session id> --issue <n>`. Never force-close; kill exact PIDs only. Never edit `.local/registry.json` by hand; only term.sh writes it. For close or park, the owner's own tab: add `--adopt` only when the owner named it or asked.

## 7. Delegate to another home (`homes.*` in `home.config`)
0. The work must have an issue in THIS home first: if the request came straight from the owner, open one (`scripts/home-log new --ready --title … --body …`) and claim it (`scripts/home-log start <n>`). The child issue is never the only record.
1. `scripts/home-log new --repo <target repo> --ready --title "<title>" --body-file scratch/brief-<n>.md`; the body's first line is `Parent: <this repo>#<n>`, then the brief and the owner's verbatim words. A peer handoff carries a brief and links only: write the brief in the target home's own terms and do not name this home's domain, clients, projects or people; the `Parent:` line is the only link back.
2. `scripts/home-log start <n>` (if this session has not claimed it yet), then `scripts/home-log checkpoint <n> --delegated <target repo>#<m>`.
3. Start the target orchestrator: helpers on → `scripts/term/term.sh survey --cwd <target path>`; if no live session runs there, `scripts/term/term.sh open <target path> --issue <m> --role orchestrator --brief "Run the orchestrate skill, then issue #<m>."` (when the child closes, close that tab with `scripts/term/term.sh close <its tty> --issue <m> --repo <target repo>`). If one is live, `scripts/term/term.sh send <its tty> "look at issue #<m>"` and nothing else. Helpers off → open nothing; the child waits as `status:ready`.
4. A question the child raised lives on the child's issue only: the parent's status links it and never copies it onto the parent issue. Never claim, checkpoint, finish or label the child's issue, and never tell a worker to claim an issue this session already claimed; only read the child. When it closes, the sweep reports it (step 2).

## 8. Proactivity (`proactivity.mode`)
- `off`: act only on what the owner says in this session.
- `assigned` (default): work `status:ready` issues; prepare draft replies for the owner to pick.
- `watch`: also check `proactivity.sources` every `proactivity.every_minutes` with the session's own scheduler; found work becomes `scripts/home-log new` (inbox) or goes to the session that owns it.
- At every level: act only while this session runs; never send a message on your own (a draft is confirmed through the ask tool; several yes/no approvals at once go on one review page with an answer per row, not a chain of questions; a draft together with other choices counts as several approvals: one review page with the draft as an editable text and yes / no / note per row, plus one pointer question); **heavy work asks first**: more than one subagent, or bulk reading, needs the owner's yes.

## 9. Close every turn
- Owner away or an unattended run: never ask; `scripts/home-log checkpoint <n> --park --question "<q>"` only. Every decision or step that waits for him is stored before the final: this session's own on an issue it holds, this way; one a worker will hit goes in that worker's brief.
- Record a hand-off (checkpoint, release, "handed to a worker") only after `term.sh open` printed the session id, tty and pid.
- Before closing an issue: every open question of the owner on it is answered or stored with `--park --question`.
- When a fallback already carries the work, always offer "leave it as is and watch" as its own option. That answer means: file a follow-up issue for the watch (`scripts/home-log new`) holding the cause hypothesis your evidence supports and its log lines, then finish (do not park).
- Write a result to the record only after you verified it (read back the effect); never report a count you did not observe.
- Before handing a step to the owner, run the check that proves what is left (an identity call, a status command) and hand over only that.
- Questions go through the ask tool (or, owner away, `scripts/home-log checkpoint <n> --park --question "<q>"`); never only in the final message.
- The final message: at most five plain lines: done, waiting for the owner, next.
