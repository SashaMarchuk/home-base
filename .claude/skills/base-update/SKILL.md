---
name: base-update
description: Take a base release into this home, or roll the last one back. Use when session-start or home-sweep says "base-ahead", or the owner says "update from base", "pull the base", "sync with base", "update to <version>", "roll back the base update".
---

# base-update

The base ships releases (tags `vX.Y.Z`, notes in its `CHANGELOG.md`). `VERSION` says which release this home is on. `scripts/base-update` is the one way to move: people run it by hand, this skill runs the same command. The base owns the paths `base.manifest` lists and the base block of `CLAUDE.md`; this home owns everything else.

1. `scripts/base-update --dry-run` (add the version the owner named, if any, older ones too; with none it takes `base.pin` from `home.config`, else the newest release). Read what it prints.
   - Exit 1 (uncommitted changes, an untracked file in the way, broken `CLAUDE.md` markers, an unknown version): fix what it names when it is this session's own change; otherwise open one owner issue (`scripts/home-log new --title "base-update needs the owner" --body-file <file> --label <labels.needs_owner>`) with its words, and stop.
   - Exit 2 (a malformed version such as `banana`): ask the owner which version was meant.
   - Exit 3 (the base cannot be reached): say so in one line and stop. Nothing changed.
2. `scripts/base-update` with the same arguments. It commits once and never pushes.
3. If it saved a patch (`.local/base-update/<name>.patch`: this home's edits to base-owned files, replaced by the release): write `scratch/base-sync.md` with the paths it listed, the release and the patch in a fenced block, then `scripts/home-log new --title "base-sync: home edits to base files" --body-file scratch/base-sync.md --label base-sync`. The issue says where each edit belongs: a rule in the home section of `CLAUDE.md`, a setting in `home.config` or `.local/config`, a script in `tools/`, a skill in `.claude/skills/<own name>/`, a fix the base needs in the base.
4. `scripts/checks/run`, then `git push origin`. If it printed `templates/settings.json changed`, apply the changed hook lines to `.claude/settings.json` by hand (keep `enabledPlugins`).
5. Roll back only when the owner asks or the checks fail after the update: `scripts/base-update --rollback`, then step 4. It makes a new commit; it never resets or force-pushes.
6. Report one line: `vA -> vB` (or rolled back to vA) / base-sync issue #n / owner issue #n.
