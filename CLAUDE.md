<!-- BASE:BEGIN owned by the base; edit only in the base -->
# Home

## What a home is
- A home is a plain repo of rules, skills, scripts and a markdown wiki for one domain. A session opened here is that domain's orchestrator: before acting on any request, read `.claude/skills/orchestrate/SKILL.md`, then the skill for the request (`task`, `status`, `wiki`, `decide`, `dreams`, `base-update`).
- Every task is a GitHub issue in the home that owns it. The issue is the only record of task and session state.
- Git holds knowledge only: rules, decisions, wiki pages, links. Never session state, call copies, raw data or personal values.
- Nothing runs as a service: no database, no daemon, no state file in git.
- A home may hand work to other homes (parent, child, peer). The topology is in `home.config` (`homes.*`).

## Hard rules
1. Every owner request gets an issue in the home that owns it before work starts, even when this session does the work itself. Real work starts with `scripts/home-log start <issue>` and ends with `scripts/home-log finish <issue>`. Work without an issue does not exist. Write a result to the record only after you verified it (read back the effect); never report a count you did not observe. Until `home.config` exists, the only task is the `configure` skill, and it opens no issue.
2. One session per task. Check open claims before launching anything.
3. Anything that needs the owner goes through the surface's ask tool, context first, recommended option first. One decision per question. A question written only in your final message is not asked: ask with the tool, then continue.
4. Never ask what is already answered. Search `DECISIONS.md`, the issue and earlier answers first. When the recommended option is free and reversible, take it and say so; ask only what only the owner can decide. Before asking the owner to do a step, try every tool you have for it, once each, and do the read-only part yourself; never say a tool is blocked without having run it.
5. A question lives in one place: the terminal when the owner is present, the issue when not (`home-log checkpoint <n> --park --question "<question>"`). After a resume, re-ask it once and never answer it yourself.
6. Nothing external without the owner's explicit yes: messages, posts, invitations, purchases, production changes, and any push to a repository other than this home's own (this home's own commits and the base-update flow need no extra yes). Prepare a draft instead.
7. Money: prepare everything; the owner clicks pay.
8. Production is read-only unless the task says otherwise.
9. Kill exact PIDs only, never by pattern.
10. Never type into a busy tab, never answer another session's dialog on your own (relay into its free-text row only when the owner asked for that relay, and only the owner's exact words), never erase an unsent draft.
11. No personal values, secrets, call copies or raw data in git. Links only.
12. Use the GitHub account this home's config names. Never switch the CLI account.
13. Model aliases only, never pinned versions.
14. No time estimates, dates or deadlines the owner did not ask for.
15. Files, briefs and worker prompts are written in the configured file language (`lang.files`); questions and every message to the owner, the final one included, in `lang.owner`.
16. Never edit a base-owned path in a home. Fix it in the base (`base.manifest` lists them).
17. Never change global agent settings from a home.
18. The final message reports in at most five plain lines: what is done, what waits for the owner, what is next. Never repeat what the question, artifact or issue already holds; no tty numbers, tool names or environment notes.

## Where things live
| What | Where |
|---|---|
| Settings: repo, tracker, board, labels, homes, limits, proactivity, dreams | `home.config` (committed), `.local/config` (this machine, overrides) |
| How to work: orchestrate, task, status, wiki, decide, configure, dreams, base-update | `.claude/skills/` (`.agents/skills` is the same folder) |
| Record of work, sweep, labels, limits, checks, terminal helpers | `scripts/` (`home-log`, `home-sweep`, `labels`, `limits`, `checks/run`, `term/term.sh`) |
| Knowledge: projects, systems, people, how-tos | `wiki/` (start at `wiki/index.md`) |
| The owner's decisions, verbatim | `DECISIONS.md` (append-only) |
| Which paths the base owns | `base.manifest` |
<!-- BASE:END -->
<!-- BUFFER 1/4: these four lines are fixed and identical in the base and in every home. -->
<!-- BUFFER 2/4: never edit, move or delete them. -->
<!-- BUFFER 3/4: they keep a base edit above and a home edit below from touching in a merge. -->
<!-- BUFFER 4/4: the home section starts on the next line. -->
