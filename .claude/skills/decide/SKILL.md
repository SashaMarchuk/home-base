---
name: decide
description: Record one owner decision in DECISIONS.md with the verbatim quote. Use when the owner decides something ("let's go with X", "from now on", "decided"), or a worker or other surface needs to log a decision the owner made.
---

# decide

1. Only the owner's own decision, or a choice the owner explicitly delegated, goes in. Your own default is not a decision: put it in an owner issue instead (`scripts/home-log checkpoint <n> --question ...` or `scripts/home-log new`).
2. Search `DECISIONS.md` first. If the same decision exists, stop. If it changes an older one, note that id.
3. Next id: continue the file's own id family. If the file's header names the family for new entries, use it. Otherwise, if the entries use one family, continue it; if they use more than one, ask the owner which family new entries use, then name it in the header. The number is the integer after the family prefix (ignore a letter suffix such as `b`); take the highest in that family plus one, with the same zero-padding: after `### D23 — ...` comes `D24`, after `### X-D007 — ...` comes `X-D008`. An empty file starts at `D1`. Never start a second series (no `D-001` next to `D1`).
4. Append at the end in the file's own entry format (the "Entry format" block at its top). Use the `###` template lines inside that block. Default, when the file has none:
   ```
   ### <ID> — <title>
   Quote: «the owner's words, verbatim, in the language spoken»
   Gloss: English rendering (required when the quote is not in English)
   Source: issue link, session id or document
   Status: active
   Kind: owner | delegated
   Decider: (delegated only) who decided, under which delegating quote
   Supersedes: (optional) the older id this entry replaces
   ```
   Plain lines, no bullets.
   A standing approval (the owner says an action needs no confirm from now on: "don't ask", "just do it", "if X, you have my yes") adds these lines after `Kind:`, titled `Standing: <action> without confirm`:
   ```
   Standing: yes
   Allows: <the action class, concrete>
   Where: <this home | a project path prefix | a window or group>
   Unless: <conditions that send it back to a question>
   Until: none (a limit only when the owner states one)
   ```
   The `Quote:` is the owner's own words: the statement, or the yes. Write only the scope the owner named; never widen it.
5. If it supersedes an older entry: change only that entry's line to `Status: superseded-by <ID>`. Never edit or delete anything else (append-only).
6. **Standing approvals list.** For an active standing entry, add one line to the `### Standing approvals` list in the home section of `CLAUDE.md` (create the heading at the end of the home section when absent): `- <ID>: <action>, <where>; unless <condition>.` Only active entries are listed. An entry whose `Status:` is not `active` gets no line.
7. **Undo.** When the owner withdraws a standing approval ("ask me again about X", "cancel that"), append a new entry with the owner's words that supersedes it (step 5), and remove its line from the list. Never `git revert` an entry: the file is append-only. When the owner says no to, edits or undoes an action done under an entry, stop using that entry for this task only, and record the owner's words as a plain entry; the standing entry stays active until the owner withdraws it.
8. No personal values in the quote; cut or paraphrase that part and say so.
9. Commit: `decision <ID>: <title>` (a withdrawal: `decision <ID>: revoke <old ID>`), with the `CLAUDE.md` line in the same commit.
