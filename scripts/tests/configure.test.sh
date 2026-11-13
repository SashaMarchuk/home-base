#!/usr/bin/env bash
# Tests scripts/configure on a throwaway copy of this repo (no network).
#   scripts/tests/configure.test.sh        exit 0 when every assertion passes
# Copies scripts/, templates/ and base.manifest into a git-initialised temp dir,
# adds a fixture CLAUDE.md, base-only paths and an origin that is the base, and
# runs configure there with an invented persona. Never touches the real repo.
# gh is the stub in scripts/tests/stubs (no network).
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd -P)
W=$(mktemp -d "${TMPDIR:-/tmp}/configure-test.XXXXXX")
trap 'rm -rf "$W"' EXIT
R="$W/home"
export PATH="$SRC/scripts/tests/stubs:$PATH" GH_STUB_DIR="$W/ghstore"
unset GH_CONFIG_DIR GH_STUB_FAIL_MATCH GH_STUB_FAIL_MESSAGE
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $*"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL $*"; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
tree_sum() { (cd "$R" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum | shasum | cut -c1-40; git config --local --list | LC_ALL=C sort | shasum | cut -c1-40); }

mkdir -p "$R"
cp -R "$SRC/scripts" "$SRC/templates" "$SRC/base.manifest" "$R/"
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
# a fresh clone of the base: base-only paths committed, origin is the base
mkdir -p "$R/openspec"; echo spec > "$R/openspec/a.md"; echo readme > "$R/README.md"
git -C "$R" add -A && git -C "$R" commit -qm clone --no-verify
git -C "$R" remote add origin https://github.com/example-org/home-base.git
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
tracker.board=taskwall
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
check "origin renamed to base" [ "$(git -C "$R" remote get-url base)" = https://github.com/example-org/home-base.git ]
check "origin is the home repo" [ "$(git -C "$R" remote get-url origin)" = https://github.com/example-org/orchard-home.git ]
check "origin push is the home repo" [ "$(git -C "$R" remote get-url --push origin)" = https://github.com/example-org/orchard-home.git ]
check "repoint reported" grep -q 'configure: origin now points to example-org/orchard-home' <<<"$out"
check "base-only folder removed" [ -z "$(git -C "$R" ls-files openspec)" ]
check "base-only folder gone from disk" [ ! -e "$R/openspec" ]
check "base-only file removed" [ -z "$(git -C "$R" ls-files README.md)" ]
check "base-only removal reported" grep -q 'configure: removed base-only path README.md' <<<"$out"
check "flowing paths kept" [ -n "$(git -C "$R" ls-files scripts/configure)" ]
check "labels not run without --labels" grep -q 'labels not run' <<<"$out"
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

# 6b. no board: board_write is not written even when answered
sed 's/^tracker.board=.*/tracker.board=none/' "$W/answers.no" > "$W/answers.noboard"
"$R2/scripts/configure" --answers "$W/answers.noboard" >/dev/null 2>&1; rc=$?
check "no board: exit 0" [ "$rc" = 0 ]
check "no board: board_write empty" grep -qx 'tracker.board_write=' "$R2/home.config"
check "board named: board_write kept" grep -qx 'tracker.board_write=read-only' "$R/home.config"

# 6c. helpers asked on, device check fails: the answers file is rewritten to off
mkdir -p "$W/notmac"; printf '#!/bin/sh\necho Linux\n' > "$W/notmac/uname"; chmod +x "$W/notmac/uname"
sed 's/^terminal_helpers=.*/terminal_helpers=on/' "$W/answers.no" > "$W/answers.on"
out=$(PATH="$W/notmac:$PATH" "$R2/scripts/configure" --answers "$W/answers.on" 2>&1); rc=$?
check "helpers on, not macOS: exit 0" [ "$rc" = 0 ]
check "helpers on, not macOS: config off" grep -qx 'terminal_helpers=off' "$R2/.local/config"
check "helpers on, not macOS: answers off" [ "$(grep '^terminal_helpers=' "$W/answers.on")" = terminal_helpers=off ]
check "helpers on, not macOS: rewrite reported" grep -q "configure: wrote $W/answers.on (terminal_helpers=off)" <<<"$out"
out=$(PATH="$W/notmac:$PATH" "$R2/scripts/configure" --answers "$W/answers.on" 2>&1)
check "helpers rewrite: second run writes nothing" sh -c "! grep -q 'configure: wrote' <<'X'
$out
X"

# 7. a failed write is an error: exit 3, the file named, never "wrote"
R3="$W/home3"; mkdir -p "$R3"; cp -R "$SRC/scripts" "$SRC/templates" "$R3/"; cp "$R/CLAUDE.md" "$R3/CLAUDE.md"
git -C "$R3" init -q; mkdir -p "$R3/home.config"   # a folder where the file must go: unwritable even as root
out=$("$R3/scripts/configure" --answers "$A" 2>&1); rc=$?
check "failed write exits 3" [ "$rc" = 3 ]
check "failed write names the file" grep -q 'cannot write home.config' <<<"$out"
check "failed write never says wrote" sh -c "! grep -q 'wrote home.config' <<'X'
$out
X"

# 8. labels: one plain line per failure, configure exit 4 says which
R4="$W/home4"; mkdir -p "$R4"; cp -R "$SRC/scripts" "$SRC/templates" "$R4/"; cp "$R/CLAUDE.md" "$R4/CLAUDE.md"
git -C "$R4" init -q
out=$(GH_STUB_FAIL_MATCH='^api repos/' GH_STUB_FAIL_MESSAGE='gh: Not Found (HTTP 404)' "$R4/scripts/configure" --answers "$A" --labels 2>&1); rc=$?
check "missing repo: exit 4" [ "$rc" = 4 ]
check "missing repo: labels one-liner" grep -qx 'labels: cannot reach example-org/orchard-home: create it on GitHub (private) and push, then run scripts/labels' <<<"$out"
check "missing repo: configure says not found" sh -c 'printf "%s
" "$1" | tail -1 | grep -q "labels are NOT created: the repo example-org/orchard-home was not found"' _ "$out"
out=$(GH_STUB_FAIL_MATCH='^label create' GH_STUB_FAIL_MESSAGE='HTTP 403: Resource not accessible by integration' "$R4/scripts/configure" --answers "$A" --labels 2>&1); rc=$?
check "no permission: exit 4" [ "$rc" = 4 ]
check "no permission: no raw error, one labels line" [ "$(grep -c 'HTTP 403' <<<"$out")$(grep -c '^labels:' <<<"$out")" = 01 ]
check "no permission: labels one-liner" grep -qx 'labels: none created: this GitHub login cannot manage labels in example-org/orchard-home. On a computer: `gh auth refresh -s repo`; in a web session: give the GitHub app access to the repository. Then run scripts/labels.' <<<"$out"
check "no permission: configure says permission" sh -c 'printf "%s
" "$1" | tail -1 | grep -q "no permission to manage labels.*in a web session: give the GitHub app access"' _ "$out"
out=$("$R4/scripts/configure" --answers "$A" --labels 2>&1); rc=$?
check "labels ok: exit 0" [ "$rc" = 0 ]
check "labels ok reported" grep -q '^labels: ok (example-org/orchard-home)' <<<"$out"
check "no origin: origin added" [ "$(git -C "$R4" remote get-url origin)" = https://github.com/example-org/orchard-home.git ]

# origin is the base and a base remote already exists: origin is re-pointed
git -C "$R4" remote set-url origin https://github.com/example-org/home-base.git
git -C "$R4" config remote.origin.pushurl DISABLED
"$R4/scripts/configure" --answers "$A" >/dev/null 2>&1; rc=$?
check "base present: exit 0" [ "$rc" = 0 ]
check "base present: origin re-pointed" [ "$(git -C "$R4" remote get-url origin)" = https://github.com/example-org/orchard-home.git ]
check "base present: origin push re-pointed" [ "$(git -C "$R4" remote get-url --push origin)" = https://github.com/example-org/orchard-home.git ]
check "base present: base push disabled" [ "$(git -C "$R4" remote get-url --push base)" = DISABLED ]

# 9. configuring the base itself is refused
sed 's#^repo=.*#repo=example-org/home-base#' "$A" > "$W/answers.base"
out=$("$R4/scripts/configure" --answers "$W/answers.base" 2>&1); rc=$?
check "base itself refused (exit 2)" [ "$rc" = 2 ]
check "base itself named" grep -q 'this is the base itself' <<<"$out"

echo "configure.test: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
