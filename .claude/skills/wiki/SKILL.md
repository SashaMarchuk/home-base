---
name: wiki
description: Maintain this home's markdown wiki. Use for "add this to the wiki", "ingest this doc/link", "what does the wiki say about X", "lint the wiki", or when knowledge from a task should be kept.
---

# wiki

Pages live in `wiki/` (`index.md`, `projects/`, `systems/`, `people/`, `me/`, `howto/`). Knowledge only: summaries and links, never call copies, raw data or personal values. `people/` holds role and channel only.

## ingest <source>
1. Read the source once. Search the wiki for every page it touches (`grep -ril`).
2. Edit those pages in place; add a page only when none fits, and link it from `wiki/index.md`.
3. Each fact once: link to the page that holds it instead of repeating it. Settings stay in `home.config`, decisions in `DECISIONS.md`.
4. Every page ends with `Sources: <files or links it was built from>`. Mark an uncertain fact `unverified`.
5. A pointer page for a code repo holds: what it is, local path, remote, GitHub account label, status, links.
6. Commit with a one-line message.

## query <question>
Search the wiki and `DECISIONS.md`; answer briefly with the page paths. Say plainly when the wiki does not know.

## lint
Find: broken links, pages missing `Sources:`, facts stated on two pages that disagree, pages that restate a `home.config` value, orphan pages. Open **one** issue listing them: `scripts/home-log new --title "Wiki lint findings" --body-file scratch/wiki-lint.md`. Never auto-fix.
