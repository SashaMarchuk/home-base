---
name: base-update
description: Pull base changes into this home and settle or escalate conflicts. Use when session-start or home-sweep says "base-ahead N", or the owner says "update from base", "pull the base", "sync with base".
---

# base-update

Plain git. The base owns the flows-down paths and the base block of `CLAUDE.md`; this home owns everything else. Lists of both are in `base.manifest`.

1. **Remote.** `git remote get-url base` fails: `git remote add base "$(bash -c '. scripts/lib/config; cfg base.url')"`. Always `git remote set-url --push base DISABLED`. Never push to the base from a home.
2. Working tree must be clean (`git status --porcelain` empty); otherwise stop and say so.
3. `PRE=$(git rev-parse HEAD)`, `git fetch base`, then `git merge --no-commit --no-ff base/main` (first time only: add `--allow-unrelated-histories` after confirming the flows-down paths are identical).
4. Remove base-only paths: for every `base-only <path>` line in `base.manifest`, `git rm -r -q --ignore-unmatch -- <path>`.
5. Settle by path owner (`git diff --name-only --diff-filter=U`):
   - **No conflict:** `git commit -m "base-update: merge base/main"`, push to `origin`. No question.
   - **Conflicts only in flows-down paths:** save the home side first (`git diff base/main "$PRE" -- <paths> > scratch/base-sync.diff`), then `git checkout --theirs -- <paths>`, `git add`, commit, push. Write `scratch/base-sync.md`: the paths, the base commit and the content of `scratch/base-sync.diff` in a fenced block. Then open one issue: `scripts/home-log new --title "base-sync: dropped home diff" --body-file scratch/base-sync.md --label base-sync` (the body is scanned like any text).
   - **Any other conflict** (the `CLAUDE.md` markers or buffer, a home-owned path): `git merge --abort`. Open one owner issue: `scripts/home-log new --title "base-update needs the owner" --body-file ... --label <labels.needs_owner>` listing the files and the base commit. Nothing else.
6. After the commit run `scripts/checks/run`. If `templates/settings.json` changed in this merge, say so and apply the changed hook lines to `.claude/settings.json` by hand (keep `enabledPlugins`).
7. Report one line: merged N commits / base-sync issue #n / owner issue #n.
