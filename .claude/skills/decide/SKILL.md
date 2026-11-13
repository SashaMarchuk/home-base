---
name: decide
description: Record one owner decision in DECISIONS.md with the verbatim quote. Use when the owner decides something ("let's go with X", "from now on", "decided"), or a worker or other surface needs to log a decision the owner made.
---

# decide

1. Only the owner's own decision, or a choice the owner explicitly delegated, goes in. Your own default is not a decision: put it in an owner issue instead (`scripts/home-log checkpoint <n> --question ...` or `scripts/home-log new`).
2. Search `DECISIONS.md` first. If the same decision exists, stop. If it changes an older one, note that id.
3. Next id: the highest `### D-NNN` plus one.
4. Append at the end, exactly:
   ```
   ### D-NNN Short title
   - Quote: "the owner's words, verbatim, in the language spoken"
   - Gloss: English rendering (required when the quote is not in English)
   - Source: issue link, session id or document
   - Supersedes: D-MMM | none
   - Status: active
   - Kind: owner | delegated
   - Decider: (delegated only) who decided, under which delegating quote
   ```
5. If it supersedes D-MMM: change only that entry's line to `- Status: superseded-by D-NNN`. Never edit or delete anything else (append-only).
6. No personal values in the quote; cut or paraphrase that part and say so.
7. Commit: `decision D-NNN: <title>`.
