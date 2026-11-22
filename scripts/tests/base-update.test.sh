#!/bin/bash
# Tests for scripts/base-update against a small local base with four releases (no network).
# Each case is one of the update eval cases: fresh home, customized home, an edited base-owned
# file, skipped releases, first update of a home with no VERSION, rollback, dry run, dirty tree,
# offline, a pin. Every rule has a fixture that must pass and one that must fail. Exit 0 when all pass.
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/base-update-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=noreply@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GH_CONFIG_DIR
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; sed -n '1,12p' "$T/out" 2>/dev/null | sed 's/^/    /' >&2; }
run() { "$@" > "$T/out" 2>&1; RC=$?; }
has() { grep -qF -- "$1" "$T/out"; }
q() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# ---------------------------------------------------------------- the base: v1.0.0 .. v1.3.0
B="$T/base"; mkdir -p "$B/scripts/lib" "$B/templates" "$B/openspec" "$B/.claude/skills/task"
cp "$SRC/scripts/base-update" "$B/scripts/"; cp "$SRC/scripts/lib/config" "$B/scripts/lib/"
cat > "$B/base.manifest" <<'EOF'
shared CLAUDE.md
flows scripts/
flows templates/
flows .claude/skills/task/
flows base.manifest
flows VERSION
base-only openspec/
base-only README.md
base-only CHANGELOG.md
EOF
claude() { # claude <base text>
  printf '<!-- BASE:BEGIN owned by the base -->\n# Home\n%s\n<!-- BASE:END -->\n' "$1"
  printf '<!-- BUFFER %s/4 -->\n' 1 2 3 4
}
claude "base rules one" > "$B/CLAUDE.md"
printf 'echo tool v1\n' > "$B/scripts/tool"; printf 'old helper\n' > "$B/scripts/old-helper"
printf '{"hooks":1}\n' > "$B/templates/settings.json"; printf 'skill v1\n' > "$B/.claude/skills/task/SKILL.md"
printf 'req\n' > "$B/openspec/r.md"; printf 'readme\n' > "$B/README.md"
changelog() { # changelog <newest> ...older
  { echo "# Changelog"; for v in "$@"; do printf '\n## [%s] - 2026-11-22\n- change in %s\n' "$v" "$v"; done; } > "$B/CHANGELOG.md"
}
release() { # release <version>
  printf '%s\n' "$1" > "$B/VERSION"
  git -C "$B" add -A && git -C "$B" commit -q -m "release $1" && git -C "$B" tag -a "v$1" -m "v$1"
}
git -C "$B" init -q -b main
git -C "$B" add -A && git -C "$B" commit -q -m "before releases: no VERSION file yet"
PRE0=$(git -C "$B" rev-parse --short HEAD)
changelog 1.0.0; release 1.0.0
printf 'echo tool v1.1\n' > "$B/scripts/tool"; printf 'new in 1.1\n' > "$B/scripts/new-thing"
changelog 1.1.0 1.0.0; release 1.1.0
git -C "$B" rm -q scripts/old-helper; claude "base rules two" > "$B/CLAUDE.md"
changelog 1.2.0 1.1.0 1.0.0; release 1.2.0
printf '{"hooks":2}\n' > "$B/templates/settings.json"; printf 'skill v1.3\n' > "$B/.claude/skills/task/SKILL.md"
changelog 1.3.0 1.2.0 1.1.0 1.0.0; release 1.3.0
printf 'unreleased work\n' > "$B/scripts/wip"; git -C "$B" add -A; git -C "$B" commit -q -m "work after 1.3.0"

mkhome() { # mkhome <dir> <base ref>: clone, then what configure does
  git clone -q "$B" "$1" && git -C "$1" checkout -q -B main "$2" 2>/dev/null
  ( cd "$1" && git rm -r -q --ignore-unmatch openspec README.md CHANGELOG.md && git remote rename origin base \
    && git remote set-url --push base DISABLED && printf '.local/\n' > .gitignore \
    && printf 'repo=test/home\nbase.url=%s\n' "$B" > home.config \
    && printf '\n## This home\n- my own rule\n' >> CLAUDE.md && git add -A && git commit -q -m configure )
}
ver() { cat "$1/VERSION"; }
same() { git -C "$1" diff --quiet "$2" HEAD -- "${@:3}"; } # same <home> <ref> <paths>: no difference

# 1. Fresh home: newest release, history records the tag, home section kept, base-only paths absent.
H="$T/fresh"; mkhome "$H" v1.0.0
run bash "$H/scripts/base-update"
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.3.0 ] && ok || bad "fresh: update to the newest release"
has "change in 1.3.0" && has "change in 1.1.0" && ! has "change in 1.0.0" && ok || bad "fresh: changelog of the skipped releases"
q "$H" merge-base --is-ancestor v1.3.0 HEAD && ok || bad "fresh: the release is recorded in history"
same "$H" v1.3.0 scripts templates .claude/skills/task base.manifest VERSION && ok || bad "fresh: base-owned paths equal the release"
[ ! -e "$H/scripts/old-helper" ] && [ ! -e "$H/scripts/wip" ] && [ ! -e "$H/openspec" ] && ok || bad "fresh: deleted and unreleased files absent"
grep -q 'base rules two' "$H/CLAUDE.md" && grep -q 'my own rule' "$H/CLAUDE.md" && ok || bad "fresh: base block new, home section kept"
[ -z "$(git -C "$H" status --porcelain)" ] && [ "$(git -C "$H" log -1 --format=%s)" = "base-update: v1.0.0 -> v1.3.0" ] && ok || bad "fresh: one clean commit"
git -C "$H" log -1 --format=%B | grep -qx 'Base-Update: v1.0.0 -> v1.3.0' && ok || bad "fresh: trailer"
has "templates/settings.json changed" && ok || bad "fresh: settings template change reported"
run bash "$H/scripts/base-update"
[ "$RC" = 0 ] && has "already on v1.3.0" && ok || bad "fresh: second run does nothing"

# 2. Customized home: own config, wiki, tool and skill untouched.
H="$T/custom"; mkhome "$H" v1.1.0
mkdir -p "$H/wiki" "$H/tools" "$H/.claude/skills/mine"
printf 'x\n' > "$H/wiki/index.md"; printf 'mine\n' > "$H/tools/t"; printf 'my skill\n' > "$H/.claude/skills/mine/SKILL.md"
printf 'base.pin=\nlimits.mode=soft\n' >> "$H/home.config"; printf -- '- second rule\n' >> "$H/CLAUDE.md"
git -C "$H" add -A; git -C "$H" commit -q -m custom
before=$(git -C "$H" rev-parse HEAD)
run bash "$H/scripts/base-update" 1.3.0
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.3.0 ] && ok || bad "custom: update"
same "$H" "$before" wiki tools .claude/skills/mine home.config .gitignore && ok || bad "custom: own files unchanged"
grep -q 'second rule' "$H/CLAUDE.md" && ! has "saved in" && ok || bad "custom: home section kept, nothing saved"

# 3. A base-owned file edited in the home: edit saved as a patch, base applied, place named.
H="$T/edited"; mkhome "$H" v1.0.0
printf 'echo my tweak\n' >> "$H/scripts/tool"; printf 'mine in base folder\n' > "$H/scripts/my-own"
sed -i.bak 's/base rules one/base rules one, changed by me/' "$H/CLAUDE.md" && rm "$H/CLAUDE.md.bak"
git -C "$H" add -A; git -C "$H" commit -q -m "edit base files"
run bash "$H/scripts/base-update"
p=$(ls "$H"/.local/base-update/*.patch 2>/dev/null | head -1)
[ "$RC" = 0 ] && [ -n "$p" ] && grep -q 'echo my tweak' "$p" && grep -q 'changed by me' "$p" && ok || bad "edited: edits saved in a patch"
same "$H" v1.3.0 scripts/tool && ! grep -q 'changed by me' "$H/CLAUDE.md" && ok || bad "edited: base content applied"
has "home section of CLAUDE.md" && has "tools/" && ok || bad "edited: says where the text belongs"
[ -f "$H/scripts/my-own" ] && has "scripts/my-own" && ok || bad "edited: own file in a base folder kept and listed"
grep -q 'scripts/new-thing' "$p" && bad "edited: untouched base files must not be in the patch" || ok
( cd "$H" && git stash -q -u 2>/dev/null; git checkout -q v1.0.0 -- scripts/tool CLAUDE.md && git apply --check "$p" ) && ok || bad "edited: the whole patch applies to the old release"
git -C "$H" checkout -q HEAD -- scripts/tool CLAUDE.md
git -C "$H" checkout -q v1.0.0 -- scripts/tool 2>/dev/null; git -C "$H" apply --include='scripts/*' "$p" 2>/dev/null && grep -q 'echo my tweak' "$H/scripts/tool" && ok || bad "edited: the patch applies to the old release"
git -C "$H" checkout -q HEAD -- scripts/tool

# 3b. The home's own files on base-only paths (README.md, openspec/) stay.
H="$T/ownreadme"; mkhome "$H" v1.0.0
printf 'my home\n' > "$H/README.md"; mkdir -p "$H/openspec"; printf 'mine\n' > "$H/openspec/mine.md"
git -C "$H" add -A; git -C "$H" commit -q -m "own readme"
run bash "$H/scripts/base-update"
[ "$RC" = 0 ] && [ "$(cat "$H/README.md")" = "my home" ] && [ -f "$H/openspec/mine.md" ] && ok || bad "own files on base-only paths are kept"

# 4. First update of an old home with no VERSION file (made before releases).
H="$T/old"; mkhome "$H" "$PRE0"
run bash "$H/scripts/base-update" --dry-run
[ "$RC" = 0 ] && has "dry run: unreleased-$PRE0 -> v1.3.0" && [ ! -f "$H/VERSION" ] && ok || bad "old: dry run names the base commit it found"
run bash "$H/scripts/base-update" 1.2.0
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.2.0 ] && ! has "saved in" && ok || bad "old: first update to a chosen release, no fake edits"

# 5. Rollback: one new commit back to the release before; then update again equals a direct update.
H="$T/roll"; mkhome "$H" v1.1.0
run bash "$H/scripts/base-update"
run bash "$H/scripts/base-update" --rollback
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.1.0 ] && same "$H" v1.1.0 scripts templates .claude/skills/task VERSION && grep -q 'base rules one' "$H/CLAUDE.md" && ok || bad "rollback: back to v1.1.0 content"
git -C "$H" log -1 --format=%B | grep -qx 'Base-Rollback: v1.3.0 -> v1.1.0' && [ "$(git -C "$H" rev-list --count HEAD)" -gt 2 ] && ok || bad "rollback: a new commit, no reset"
run bash "$H/scripts/base-update" --rollback
[ "$RC" = 1 ] && has "nothing to roll back" && ok || bad "rollback: a second rollback refuses"
run bash "$H/scripts/base-update"
[ "$RC" = 0 ] && same "$H" v1.3.0 scripts templates .claude/skills/task base.manifest VERSION && [ ! -e "$H/scripts/old-helper" ] && ! has "saved in" && ok || bad "rollback: update after rollback equals a direct update"
H2="$T/roll-old"; mkhome "$H2" "$PRE0"
run bash "$H2/scripts/base-update"
run bash "$H2/scripts/base-update" --rollback
[ "$RC" = 1 ] && has "no release" && [ "$(ver "$H2")" = 1.3.0 ] && ok || bad "rollback: refuses when the home was on no release before"

# 6. Dry run changes nothing (files, refs, worktrees).
H="$T/dry"; mkhome "$H" v1.0.0
head=$(git -C "$H" rev-parse HEAD)
run bash "$H/scripts/base-update" --dry-run
[ "$RC" = 0 ] && has "nothing was changed" && has "scripts/tool" && ok || bad "dry: prints the changes"
[ "$(git -C "$H" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$H" status --porcelain)" ] && [ "$(ver "$H")" = 1.0.0 ] \
  && [ "$(git -C "$H" worktree list | wc -l | tr -d ' ')" = 1 ] && ok || bad "dry: nothing changed"
run bash "$H/scripts/base-update" --rollback --dry-run
[ "$RC" = 1 ] && ok || bad "dry: rollback with nothing recorded refuses"

# 7. A dirty tree is refused; an untracked file is fine.
H="$T/dirty"; mkhome "$H" v1.0.0
printf 'x\n' >> "$H/home.config"
run bash "$H/scripts/base-update"
[ "$RC" = 1 ] && has "commit or stash" && [ "$(ver "$H")" = 1.0.0 ] && ok || bad "dirty: refused"
git -C "$H" checkout -q home.config; printf 'note\n' > "$H/untracked-note"
run bash "$H/scripts/base-update"
[ "$RC" = 0 ] && [ -f "$H/untracked-note" ] && ok || bad "dirty: an untracked file does not block"
H="$T/collide"; mkhome "$H" v1.0.0
printf 'mine\n' > "$H/scripts/new-thing"
run bash "$H/scripts/base-update"
[ "$RC" = 1 ] && has "scripts/new-thing" && [ "$(cat "$H/scripts/new-thing")" = mine ] && ok || bad "dirty: an untracked file where the release puts one is refused"

H="$T/folder"; mkhome "$H" v1.0.0
mkdir -p "$B/scripts/new-thing.d"; printf 'x\n' > "$B/scripts/new-thing.d/x"; printf '1.3.1\n' > "$B/VERSION"
git -C "$B" add -A; git -C "$B" commit -q -m "release 1.3.1"; git -C "$B" tag -a v1.3.1 -m v1.3.1
printf 'my notes\n' > "$H/scripts/new-thing.d"
run bash "$H/scripts/base-update" --dry-run
[ "$RC" = 1 ] && has "scripts/new-thing.d" && ok || bad "folder: a dry run refuses a file where the release needs a folder"
run bash "$H/scripts/base-update"
[ "$RC" = 1 ] && [ "$(cat "$H/scripts/new-thing.d")" = "my notes" ] && ok || bad "folder: an untracked file where the release needs a folder is kept and refused"
git -C "$H" add -A; git -C "$H" commit -q -m "own file"
run bash "$H/scripts/base-update"
[ "$RC" = 1 ] && [ "$(cat "$H/scripts/new-thing.d")" = "my notes" ] && ok || bad "folder: a tracked home file where the release needs a folder is refused"
git -C "$B" tag -d v1.3.1 >/dev/null; git -C "$B" reset -q --hard HEAD~1

# 7b. A release that turns a base file into a folder, and one that turns it back.
H="$T/shape"; mkhome "$H" v1.0.0
git -C "$B" rm -q scripts/tool; mkdir -p "$B/scripts/tool"; printf 'now a folder\n' > "$B/scripts/tool/main"; printf '1.4.0\n' > "$B/VERSION"
git -C "$B" add -A; git -C "$B" commit -q -m "release 1.4.0"; git -C "$B" tag -a v1.4.0 -m v1.4.0
git -C "$B" rm -q -r scripts/tool; printf 'a file again\n' > "$B/scripts/tool"; printf '1.5.0\n' > "$B/VERSION"
git -C "$B" add -A; git -C "$B" commit -q -m "release 1.5.0"; git -C "$B" tag -a v1.5.0 -m v1.5.0
run bash "$H/scripts/base-update" 1.4.0
[ "$RC" = 0 ] && [ -f "$H/scripts/tool/main" ] && ok || bad "shape: a base file becomes a folder"
run bash "$H/scripts/base-update" 1.5.0
[ "$RC" = 0 ] && [ "$(cat "$H/scripts/tool")" = "a file again" ] && ok || bad "shape: a base folder becomes a file"
git -C "$B" tag -d v1.4.0 v1.5.0 >/dev/null; git -C "$B" reset -q --hard HEAD~2

# 8. Offline: clear message, exit 3, nothing changed; rollback still works offline.
H="$T/offline"; mkhome "$H" v1.0.0
run bash "$H/scripts/base-update" 1.1.0
git -C "$H" remote set-url base "$T/nowhere"
run bash "$H/scripts/base-update"
[ "$RC" = 3 ] && has "cannot reach the base" && [ "$(ver "$H")" = 1.1.0 ] && ok || bad "offline: refused with exit 3"
run bash "$H/scripts/base-update" --rollback
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.0.0 ] && ok || bad "offline: rollback works"

# 9. Pin, older target, bad version, check, markers.
H="$T/pin"; mkhome "$H" v1.0.0
printf 'base.pin=1.1\n' >> "$H/home.config"; git -C "$H" commit -q -am pin
run bash "$H/scripts/base-update" --check
has "target v1.1.0 (pinned to 1.1)" && has "current v1.0.0" && has "newest v1.3.0" && ok || bad "pin: check"
run bash "$H/scripts/base-update"
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.1.0 ] && ok || bad "pin: update stops at the pin"
run bash "$H/scripts/base-update" 1.0.0
[ "$RC" = 0 ] && [ "$(ver "$H")" = 1.0.0 ] && same "$H" v1.0.0 scripts templates VERSION && ok || bad "an older chosen release is applied"
run bash "$H/scripts/base-update" banana
[ "$RC" = 2 ] && ok || bad "bad version is a usage error"
run bash "$H/scripts/base-update" 9.9.9
[ "$RC" = 1 ] && has "no release v9.9.9" && ok || bad "unknown release refused"
H="$T/markers"; mkhome "$H" v1.0.0
grep -v 'BUFFER 4/4' "$H/CLAUDE.md" > "$T/c"; cp "$T/c" "$H/CLAUDE.md"; git -C "$H" commit -q -am "broken markers"
run bash "$H/scripts/base-update"
[ "$RC" = 1 ] && has "BUFFER" && ok || bad "broken CLAUDE.md markers refused"
run sh -c "cd '$H' && bash '$B/scripts/base-update'"
[ "$RC" = 1 ] && has "not in the base" && [ "$(git -C "$H" log -1 --format=%s)" = "broken markers" ] && ok || bad "the base's copy refuses, even when run from inside a home"

# 10. The sweep: a newer release, drift against the release the home is on, quiet when pinned and current.
export PATH="$SRC/scripts/tests/stubs:$PATH" GH_STUB_DIR="$T/ghstore" HOME_LOG_SETTLE=0; mkdir -p "$GH_STUB_DIR"
H="$T/sweep"; mkhome "$H" v1.1.0; cp "$SRC/scripts/home-sweep" "$H/scripts/"
printf 'echo my tweak\n' >> "$H/scripts/tool"; git -C "$H" commit -q -am tweak
run sh -c "cd '$H' && scripts/home-sweep"
has "SWEEP base-ahead test/home base release v1.3.0 is out (this home is on v1.1.0)" && ok || bad "sweep: newer release reported"
has "SWEEP drift test/home scripts/" && ! has "SWEEP drift test/home templates/" && ok || bad "sweep: drift against v1.1.0 only where the home edited"
printf 'base.pin=1.1\n' >> "$H/home.config"; git -C "$H" checkout -q v1.1.0 -- scripts/tool; git -C "$H" commit -q -am "pin, untweak"
run sh -c "cd '$H' && scripts/home-sweep"
! has "base-ahead" && ! has "drift" && ok || bad "sweep: quiet when on the pinned release"

# 11. Before the base has any release, the sweep compares with base/main.
B2="$T/base-norel"; git clone -q "$B" "$B2"; git -C "$B2" tag -l | while read -r t; do git -C "$B2" tag -d "$t" >/dev/null; done
H="$T/sweep-norel"; git clone -q "$B2" "$H"; git -C "$H" checkout -q -B main HEAD~2
( cd "$H" && git remote rename origin base && git rm -q VERSION && printf 'repo=test/home\n' > home.config && printf '.local/\n' > .gitignore && git add -A && git commit -q -m home )
cp "$SRC/scripts/home-sweep" "$SRC/scripts/base-update" "$H/scripts/"; git -C "$H" add -A; git -C "$H" commit -q -m "new scripts"
run sh -c "cd '$H' && scripts/home-sweep < /dev/null"
has "SWEEP base-ahead test/home base/main is" && ok || bad "sweep: before any release it compares with base/main"

echo "base-update tests: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
