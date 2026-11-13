#!/usr/bin/env bash
# Tests scripts/configure on a throwaway copy of this repo (no network).
#   scripts/tests/configure.test.sh        exit 0 when every assertion passes
# Copies scripts/ and templates/ into a git-initialised temp dir, adds a fixture
# CLAUDE.md, and runs configure there with an invented persona. Never touches
# the real repo.
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd -P)
W=$(mktemp -d "${TMPDIR:-/tmp}/configure-test.XXXXXX")
trap 'rm -rf "$W"' EXIT
R="$W/home"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $*"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL $*"; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
tree_sum() { (cd "$R" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum | shasum | cut -c1-40; git config --local --list | LC_ALL=C sort | shasum | cut -c1-40); }

mkdir -p "$R"
cp -R "$SRC/scripts" "$SRC/templates" "$R/"
git -C "$R" init -q
git -C "$R" config user.name tester
git -C "$R" config user.email tester@users.noreply.github.com
cat > "$R/CLAUDE.md" <<'EOF'
<!-- BASE:BEGIN owned by the base; edit only in the base -->
# Home
Base block fixture.
<!-- BASE:END -->
<!-- BUFFER 1/4: these four lines are fixed and identical in the base and in every home. -->
<!-- BUFFER 2/4: never edit, move or delete them. -->
<!-- BUFFER 3/4: they keep a base edit above and a home edit below from touching in a merge. -->
<!-- BUFFER 4/4: the home section starts on the next line. -->
old home section
EOF
ln -s CLAUDE.md "$R/AGENTS.md"
mkdir -p "$R/.claude/skills" "$R/.agents"; ln -s ../.claude/skills "$R/.agents/skills"
BASE_BLOCK=$(sed -n '1,/BUFFER 4\/4/p' "$R/CLAUDE.md")
mkdir -p "$R/.local"
printf 'lang.owner=fr\nterminal_helpers=on\n' > "$R/.local/config"   # an override that must be kept

# invented persona
A="$W/answers"
cat > "$A" <<'EOF'
# invented persona
repo=example-org/orchard-home
owner.names=Jordan Sample
home.domain=An orchard cooperative: harvest plans and volunteer rota
home.boundary=Anything from the owner's day job
home.rules=Plain words, recommended option first.
home.rules=Never contact a buyer without the owner's yes.
lang.files=en
lang.owner=en
tracker.board=clickup
tracker.board_write=read-only
labels.needs_owner=needs-owner
base.url=https://github.com/example-org/home-base.git
homes.cellar.repo=example-org/cellar-home
homes.cellar.path=~/homes/cellar-home
homes.cellar.role=child
limits.mode=soft
proactivity.mode=assigned
dreams.mode=manual
guard.extra=docker compose down
plugins=plugin-a@example-market, plugin-b@example-market
accounts.multi=yes
accounts.rows=orchard | the co-op workspace | the workspace CLI's own config
accounts.rows=personal | everything else | the GitHub CLI config directory
terminal_helpers=off
transcripts.exclude=~/sandbox
EOF

# 1. missing keys: exit 2, every missing key named, nothing written
grep -vE '^(home\.domain|dreams\.mode|plugins)=' "$A" > "$W/answers.missing"
before=$(tree_sum)
out=$("$R/scripts/configure" --answers "$W/answers.missing" 2>&1); rc=$?
check "missing keys exit 2" [ "$rc" = 2 ]
for k in home.domain dreams.mode plugins; do
  check "missing key named: $k" grep -q "missing answer: $k" <<<"$out"
done
check "missing keys write nothing" [ "$before" = "$(tree_sum)" ]

# 2. invalid values and an address in accounts rows
AT=@   # the fake address is built at run time, so none sits in this file
sed -e 's/^limits.mode=soft/limits.mode=sometimes/' -e "s/^accounts.rows=orchard |/accounts.rows=jo${AT}example.org |/" "$A" > "$W/answers.bad"
out=$("$R/scripts/configure" --answers "$W/answers.bad" 2>&1); rc=$?
check "invalid values exit 2" [ "$rc" = 2 ]
check "invalid enum named" grep -q "invalid answer: limits.mode=sometimes" <<<"$out"
check "address refused" grep -q "holds an address" <<<"$out"
check "invalid values write nothing" [ "$before" = "$(tree_sum)" ]

# 3. the real run
out=$("$R/scripts/configure" --answers "$A" 2>&1); rc=$?
[ "$rc" = 0 ] || printf '%s\n' "$out"
check "configure exits 0" [ "$rc" = 0 ]
for f in home.config .local/config CLAUDE.md .claude/settings.json .gitignore wiki/index.md wiki/howto/accounts.md DECISIONS.md; do
  check "file written: $f" [ -f "$R/$f" ]
done
check "home.config repo" grep -qx 'repo=example-org/orchard-home' "$R/home.config"
check "home.config board_write" grep -qx 'tracker.board_write=read-only' "$R/home.config"
check "home.config default kept" grep -qx 'sweep.stale_hours=6' "$R/home.config"
check "home.config guard.extra" grep -qx 'guard.extra=docker compose down' "$R/home.config"
check "home.config homes" grep -qx 'homes.cellar.role=child' "$R/home.config"
check "home.config has no machine key" sh -c "! grep -qE '^(gh\.config_dir|terminal_helpers|transcripts\.|limits\.reader|launch\.|guard\.private_values)=' '$R/home.config'"
check "home.config has no owner name" sh -c "! grep -q 'Jordan' '$R/home.config'"
check ".local/config machine key" grep -qx 'transcripts.exclude=~/sandbox' "$R/.local/config"
check ".local/config helpers off" grep -qx 'terminal_helpers=off' "$R/.local/config"
check ".local/config override kept" grep -qx 'lang.owner=fr' "$R/.local/config"
check ".local/config no stale helpers line" [ "$(grep -c '^terminal_helpers=' "$R/.local/config")" = 1 ]
check "base block byte-identical" [ "$BASE_BLOCK" = "$(sed -n '1,/BUFFER 4\/4/p' "$R/CLAUDE.md")" ]
check "home section replaced" sh -c "! grep -q 'old home section' '$R/CLAUDE.md'"
check "home section owner" grep -q 'Owner(s): Jordan Sample' "$R/CLAUDE.md"
check "home section rule" grep -qx -- "- Never contact a buyer without the owner's yes." "$R/CLAUDE.md"
check "no placeholder left" sh -c "! grep -q '{{' '$R/CLAUDE.md' '$R/wiki/index.md' '$R/wiki/howto/accounts.md'"
check "settings plugins" [ "$(jq -c '.enabledPlugins' "$R/.claude/settings.json")" = '{"plugin-a@example-market":true,"plugin-b@example-market":true}' ]
check "settings hooks" [ "$(jq -r '.hooks.PreToolUse[1].matcher' "$R/.claude/settings.json")" = 'Write|Edit|MultiEdit' ]
check "template lists no plugin" [ "$(jq 'has("enabledPlugins")' "$R/templates/settings.json")" = false ]
check "gitignore .local/" grep -qx '.local/' "$R/.gitignore"
check "accounts row" grep -qx '| orchard | the co-op workspace | the workspace CLI'"'"'s own config |' "$R/wiki/howto/accounts.md"
check "hooksPath set" [ "$(git -C "$R" config --local core.hooksPath)" = .githooks ]
check "base remote push disabled" [ "$(git -C "$R" remote get-url --push base)" = DISABLED ]
check "completeness lists keys" grep -q '^  sweep.stale_hours=6 (default)' <<<"$out"
check "completeness lists machine keys" grep -q '^  limits.reader=none (default)' <<<"$out"

# 4. idempotent
s1=$(tree_sum)
out2=$("$R/scripts/configure" --answers "$A" 2>&1); rc=$?
check "second run exits 0" [ "$rc" = 0 ]
check "second run changes nothing" [ "$s1" = "$(tree_sum)" ]
check "second run writes no file" sh -c "! grep -q 'configure: wrote' <<'X'
$out2
X"

# 5. the repo's own checks accept the result (staged mode)
git -C "$R" add -A >/dev/null 2>&1
if [ -x "$R/scripts/checks/run" ]; then
  cout=$(cd "$R" && scripts/checks/run --staged 2>&1); rc=$?
  [ "$rc" = 0 ] || printf '%s\n' "$cout"
  check "scripts/checks/run --staged passes" [ "$rc" = 0 ]
fi

# 6. accounts.multi=no leaves no accounts page; plugins empty removes enabledPlugins
R2="$W/home2"; mkdir -p "$R2"; cp -R "$SRC/scripts" "$SRC/templates" "$R2/"; cp "$R/CLAUDE.md" "$R2/CLAUDE.md"
git -C "$R2" init -q
sed -e 's/^accounts.multi=yes/accounts.multi=no/' -e '/^accounts.rows=/d' -e 's/^plugins=.*/plugins=/' "$A" > "$W/answers.no"
"$R2/scripts/configure" --answers "$W/answers.no" >/dev/null 2>&1; rc=$?
check "multi=no exits 0" [ "$rc" = 0 ]
check "multi=no: no accounts page" [ ! -f "$R2/wiki/howto/accounts.md" ]
check "empty plugins: no enabledPlugins" [ "$(jq 'has("enabledPlugins")' "$R2/.claude/settings.json")" = false ]

echo "configure.test: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
