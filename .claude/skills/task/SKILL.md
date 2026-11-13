---
name: task
description: Turn a plain request into a clear task issue. Use when the owner says "new task", "add a task", "make an issue", "remember to do X", "queue this", or when a status:inbox issue needs grilling into status:ready.
---

# task

1. Search first: open issues (`gh api -X GET search/issues -f q='is:open is:issue repo:<repo> <words>' --jq '.items[] | "#\(.number) \(.title)"'`), `DECISIONS.md` and the wiki. If the task exists, say so and stop.
2. Grill until the task has: an **outcome** (what is true when done), a **scope** (what is in, what is out), and **done-criteria** (checkable). Use the surface's ask tool, at most four questions per round, context first, recommended option first. Never ask what is already answered.
3. Decide the home: if the task belongs to another home's domain (`homes.*`, its boundary), use the delegation steps of the `orchestrate` skill instead.
4. Write the body to `scratch/task-body.md`:
   ```
   Outcome: ...
   Scope: in ... / out ...
   Done when:
   - [ ] ...
   Owner's words (verbatim): "..."
   Links: ...
   ```
   Links only: no personal values, no call copies, no raw data.
5. Create it: `scripts/home-log new --title "<short title>" --body-file scratch/task-body.md --ready` (leave out `--ready` when still unclear: it stays `status:inbox`). Exit 4 means the text matched a personal-value pattern: change the text.
6. For an existing inbox issue: edit its body with the result (`gh api -X PATCH repos/<repo>/issues/<n> -F body=@scratch/task-body.md`) and move it to `status:ready` (`gh api -X DELETE repos/<repo>/issues/<n>/labels/status:inbox`, then `gh api -X POST repos/<repo>/issues/<n>/labels -f 'labels[]=status:ready'`).
7. Reply with the issue number and title, one line. Ask clarifying questions only with the ask tool (owner away: `scripts/home-log checkpoint <n> --park --question "<q>"`), never only in the reply.
