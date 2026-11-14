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
5. If it supersedes an older entry: change only that entry's line to `Status: superseded-by <ID>`. Never edit or delete anything else (append-only).
6. No personal values in the quote; cut or paraphrase that part and say so.
7. Commit: `decision <ID>: <title>`.
