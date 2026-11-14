#!/usr/bin/env bash
# Tests scripts/configure on a throwaway copy of this repo (no network).
#   scripts/tests/configure.test.sh        exit 0 when every assertion passes
# Copies scripts/, templates/ and base.manifest into a git-initialised temp dir,
# adds a fixture CLAUDE.md, base-only paths and an origin that is the base, and
# runs configure there with example values. Never touches the real repo.
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

# example values
A="$W/answers"
cat > "$A" <<'EOF'
# example values
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
check "home.config sweep lookback default" grep -qx 'sweep.lookback_days=14' "$R/home.config"
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
check "missing repo: the remaining line" sh -c 'printf "%s\n" "$1" | tail -1 | grep -qxF "configure: the files are written, but the labels are NOT created: the repo example-org/orchard-home was not found on GitHub. Create it (private), then run this line from your own terminal: cd $2 && scripts/labels"' _ "$out" "$(cd "$R4" && pwd -P)"
out=$(GH_STUB_FAIL_MATCH='^label create' GH_STUB_FAIL_MESSAGE='HTTP 403: Resource not accessible by integration' "$R4/scripts/configure" --answers "$A" --labels 2>&1); rc=$?
check "no permission: exit 4" [ "$rc" = 4 ]
check "no permission: no raw error, one labels line" [ "$(grep -c 'HTTP 403' <<<"$out")$(grep -c '^labels:' <<<"$out")" = 01 ]
check "no permission: labels one-liner" grep -qx 'labels: none created: this GitHub login cannot manage labels in example-org/orchard-home. On a computer: `gh auth refresh -s repo`; in a web session: on github.com/settings/installations open Claude, Configure, and add this repository with read and write access. Then run scripts/labels.' <<<"$out"
check "no permission: configure says permission" sh -c 'printf "%s
" "$1" | tail -1 | grep -q "no permission to manage labels.*In a web session: on github.com/settings/installations open Claude"' _ "$out"
R4P=$(cd "$R4" && pwd -P)
check "no permission: the remaining line" sh -c 'printf "%s\n" "$1" | tail -1 | grep -qF "run this line from your own terminal: cd $2 && gh auth refresh -s repo && scripts/labels"' _ "$out" "$R4P"
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

# 10. the session may not change git settings: every other step is done, exit 0 with a pending line, then a normal run finishes
R5="$W/home5"; mkdir -p "$R5"
cp -R "$SRC/scripts" "$SRC/templates" "$SRC/base.manifest" "$R5/"; cp "$R/CLAUDE.md" "$R5/CLAUDE.md"
mkdir -p "$R5/openspec"; echo spec > "$R5/openspec/a.md"; echo readme > "$R5/README.md"
git -C "$R5" init -q; git -C "$R5" add -A
git -C "$R5" -c user.name=tester -c user.email=tester@users.noreply.github.com commit -qm clone --no-verify
git -C "$R5" remote add origin https://github.com/example-org/home-base.git
R5P=$(cd "$R5" && pwd -P)
REAL_GIT=$(command -v git); mkdir -p "$W/lockedgit" "$W/lockedremote"
cat > "$W/lockedgit/git" <<EOF
#!/bin/sh
sub=\$1; [ "\$1" = -C ] && sub=\$3
[ "\$sub" = config ] && { echo "error: could not lock config file .git/config: Operation not permitted" >&2; exit 255; }
exec "$REAL_GIT" "\$@"
EOF
cat > "$W/lockedremote/git" <<EOF
#!/bin/sh
[ "\$1" = -C ] && [ "\$3" = remote ] && [ "\$4" != get-url ] && { echo "error: could not lock config file .git/config: Operation not permitted" >&2; exit 255; }
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$W/lockedgit/git" "$W/lockedremote/git"
out=$(PATH="$W/lockedgit:$PATH" "$R5/scripts/configure" --answers "$A" --labels 2>&1); rc=$?
pend=$(printf '%s\n' "$out" | sed -n 's/^pending: //p')
check "git refused: exit 0" [ "$rc" = 0 ]
check "git refused: files written" grep -qx 'repo=example-org/orchard-home' "$R5/home.config"
check "git refused: base-only folder gone from disk" [ ! -e "$R5/openspec" ]
check "git refused: base-only file gone from disk" [ ! -e "$R5/README.md" ]
check "git refused: one pending line" [ "$(grep -c '^pending: ' <<<"$out")" = 1 ]
check "git refused: pending starts in the root" [ "${pend#cd $R5P && }" != "$pend" ]
check "git refused: pending drops base-only paths" grep -qF 'git rm -rq --cached --ignore-unmatch -- ' <<<"$pend"
check "git refused: pending renames origin" grep -qF 'git remote rename origin base && ' <<<"$pend"
check "git refused: pending disables base push" grep -qF 'git remote set-url --push base DISABLED' <<<"$pend"
check "git refused: pending adds origin" grep -qF 'git remote add origin https://github.com/example-org/orchard-home.git' <<<"$pend"
check "git refused: pending sets hooks path" grep -qF 'git config core.hooksPath .githooks' <<<"$pend"
check "git refused: labels still run" grep -q '^labels: ok' <<<"$out"
out=$(PATH="$W/lockedgit:$PATH" GH_STUB_FAIL_MATCH='^api repos/' GH_STUB_FAIL_MESSAGE='gh: Not Found (HTTP 404)' "$R5/scripts/configure" --answers "$A" --labels 2>&1); rc=$?
check "git refused, repo missing: exit 4" [ "$rc" = 4 ]
check "git refused, repo missing: one line holds the pending steps, upload and labels" sh -c 'printf "%s\n" "$1" | tail -1 | grep -qF "run this line from your own terminal: $2 && git add -A && git commit -m \"Configure home\" && git push -u origin HEAD && scripts/labels"' _ "$out" "$pend"
check "git refused: hooksPath not set" [ -z "$(git -C "$R5" config --local core.hooksPath)" ]
check "git refused: origin still the base" [ "$(git -C "$R5" remote get-url origin)" = https://github.com/example-org/home-base.git ]
# the pending line itself finishes the git part (on a copy, so the normal run below starts from the same state)
R6="$W/home6"; cp -R "$R5" "$R6"; R6P=$(cd "$R6" && pwd -P)
(eval "${pend/#cd $R5P /cd $R6P }") >/dev/null 2>&1; rc=$?
check "pending line runs" [ "$rc" = 0 ]
check "pending line: base-only paths out of the index" [ -z "$(git -C "$R6" ls-files openspec README.md)" ]
check "pending line: origin re-pointed" [ "$(git -C "$R6" remote get-url origin)" = https://github.com/example-org/orchard-home.git ]
check "pending line: base push disabled" [ "$(git -C "$R6" remote get-url --push base)" = DISABLED ]
check "pending line: hooksPath set" [ "$(git -C "$R6" config --local core.hooksPath)" = .githooks ]
# a refusal after the probe allowed git: exit 5 with the full rerun line
out=$(PATH="$W/lockedremote:$PATH" "$R5/scripts/configure" --answers "$A" 2>&1); rc=$?
check "late refusal: exit 5" [ "$rc" = 5 ]
check "late refusal: full rerun line" sh -c 'printf "%s\n" "$1" | tail -1 | grep -qF "run this line from your own terminal: cd $2 && scripts/configure --answers $3"' _ "$out" "$R5P" "$A"
out=$("$R5/scripts/configure" --answers "$A" 2>&1); rc=$?
check "rerun: exit 0" [ "$rc" = 0 ]
check "rerun: no pending line" sh -c "! grep -q '^pending:' <<'X'
$out
X"
check "rerun: base-only paths out of the index" [ -z "$(git -C "$R5" ls-files openspec README.md)" ]
check "rerun: hooksPath set" [ "$(git -C "$R5" config --local core.hooksPath)" = .githooks ]
check "rerun: base push disabled" [ "$(git -C "$R5" remote get-url --push base)" = DISABLED ]
check "rerun: origin is the home repo" [ "$(git -C "$R5" remote get-url origin)" = https://github.com/example-org/orchard-home.git ]

# 11. language names instead of codes are refused; launch.command is one word and lands in .local/config
{ cat "$W/answers.no"; echo launch.command=codex; } > "$W/answers.codex"
"$R2/scripts/configure" --answers "$W/answers.codex" >/dev/null 2>&1; rc=$?
check "launch.command answer: exit 0" [ "$rc" = 0 ]
check "launch.command answer written" grep -qx 'launch.command=codex' "$R2/.local/config"
sed 's/^launch.command=.*/launch.command=codex --yolo/' "$W/answers.codex" > "$W/answers.cmdbad"
out=$("$R2/scripts/configure" --answers "$W/answers.cmdbad" 2>&1); rc=$?
check "launch.command with a space refused (exit 2)" [ "$rc" = 2 ]
check "launch.command named" grep -q 'invalid answer: launch.command=codex --yolo' <<<"$out"
sed 's/^lang.files=en/lang.files=English/' "$A" > "$W/answers.lang"
out=$("$R4/scripts/configure" --answers "$W/answers.lang" 2>&1); rc=$?
check "language name refused (exit 2)" [ "$rc" = 2 ]
check "language name named" grep -q 'invalid answer: lang.files=English (a two-letter language code' <<<"$out"

# 12. --set / --get change machine keys in .local/config only
R7="$W/home7"; mkdir -p "$R7"; cp -R "$SRC/scripts" "$SRC/templates" "$R7/"
printf 'repo=example-org/orchard-home\ngh.config_dir=~/ghdir\n' > "$R7/home.config"
HC7=$(shasum "$R7/home.config")
out=$("$R7/scripts/configure" --get launch.profile.worker 2>&1); rc=$?
check "get with no .local: exit 0" [ "$rc" = 0 ]
check "get with no .local: default printed" [ "$out" = "launch.profile.worker=" ]
check "get writes nothing" [ ! -e "$R7/.local" ]
check "get: home.config value for a non-launch key" [ "$("$R7/scripts/configure" --get gh.config_dir)" = "gh.config_dir=~/ghdir" ]
out=$("$R7/scripts/configure" --set launch.profile.worker=personal --set launch.profile_flag=-p 2>&1); rc=$?
check "set: exit 0" [ "$rc" = 0 ]
check "set: effective values printed" [ "$out" = "launch.profile.worker=personal"$'\n'"launch.profile_flag=-p" ]
check "set: written to .local/config" grep -qx 'launch.profile.worker=personal' "$R7/.local/config"
printf 'lang.owner=fr\n' >> "$R7/.local/config"
"$R7/scripts/configure" --set launch.profile.worker=work >/dev/null 2>&1
check "set again: value replaced, one line" [ "$(grep -c '^launch.profile.worker=' "$R7/.local/config")" = 1 ]
check "set again: new value" [ "$("$R7/scripts/configure" --get launch.profile.worker)" = "launch.profile.worker=work" ]
check "set: other lines kept" grep -qx 'lang.owner=fr' "$R7/.local/config"
lc=$(shasum "$R7/.local/config")
"$R7/scripts/configure" --set launch.profile.worker=work >/dev/null 2>&1
check "set: idempotent" [ "$(shasum "$R7/.local/config")" = "$lc" ]
check "set: home.config untouched" [ "$(shasum "$R7/home.config")" = "$HC7" ]
out=$("$R7/scripts/configure" --set launch.profile.worker= 2>&1); rc=$?
check "unset: exit 0" [ "$rc" = 0 ]
check "unset: line removed" sh -c "! grep -q '^launch.profile.worker=' '$R7/.local/config'"
check "unset: default printed" [ "$out" = "launch.profile.worker=" ]
check "unset launch.command: default claude" [ "$("$R7/scripts/configure" --set launch.command= )" = "launch.command=claude" ]
lc=$(shasum "$R7/.local/config")
out=$("$R7/scripts/configure" --set launch.profile.worker=ok --set guard.private_values=x 2>&1); rc=$?
check "refused key: exit 2" [ "$rc" = 2 ]
check "refused key: named" grep -q 'refused: guard.private_values cannot be set here' <<<"$out"
check "refused key: nothing written" [ "$(shasum "$R7/.local/config")" = "$lc" ]
out=$("$R7/scripts/configure" --set repo=example-org/other 2>&1); rc=$?
check "refused committed key: exit 2" [ "$rc" = 2 ]
check "refused committed key: named" grep -q 'refused: repo is a committed key of home.config' <<<"$out"
check "refused committed key: home.config untouched" [ "$(shasum "$R7/home.config")" = "$HC7" ]
check "refused committed key: .local/config untouched" [ "$(shasum "$R7/.local/config")" = "$lc" ]
out=$("$R7/scripts/configure" --set "launch.profile.worker=two words" --set launch.model=claude-opus-4-1 2>&1); rc=$?
check "two-word profile and pinned model refused: exit 2" [ "$rc" = 2 ]
check "two-word profile named" grep -q 'refused: launch.profile.worker=two words (one word' <<<"$out"
check "pinned model named" grep -q 'refused: launch.model=claude-opus-4-1 (an alias' <<<"$out"
check "refused values: nothing written" [ "$(shasum "$R7/.local/config")" = "$lc" ]
check "--set with --answers refused" sh -c "! '$R7/scripts/configure' --answers '$A' --set launch.model=opus >/dev/null 2>&1"
# a later answers run keeps a profile set with --set
"$R2/scripts/configure" --set launch.profile.worker=personal >/dev/null 2>&1
"$R2/scripts/configure" --answers "$W/answers.codex" >/dev/null 2>&1; rc=$?
check "answers rerun after --set: exit 0" [ "$rc" = 0 ]
check "answers rerun keeps the profile" grep -qx 'launch.profile.worker=personal' "$R2/.local/config"
# a later answers run keeps the Standing approvals list the decide skill wrote, and adds none when absent
"$R2/scripts/configure" --answers "$W/answers.codex" >/dev/null 2>&1
check "answers rerun without a list adds none" sh -c "! grep -q '^### Standing approvals' '$R2/CLAUDE.md'"
printf '\n### Standing approvals\n- D9: close named sessions, this home; unless a draft.\n' >> "$R2/CLAUDE.md"
"$R2/scripts/configure" --answers "$W/answers.codex" >/dev/null 2>&1; rc=$?
check "answers rerun with a list: exit 0" [ "$rc" = 0 ]
check "answers rerun keeps the Standing approvals list" grep -qx -- '- D9: close named sessions, this home; unless a draft.' "$R2/CLAUDE.md"
check "answers rerun keeps the list once" [ "$(grep -c '^### Standing approvals' "$R2/CLAUDE.md")" = 1 ]

# 13. .codex/config.toml mirrors the plugins; lines outside the marked block are kept; drift is reported
toml_ok() { python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }
CT="$R/.codex/config.toml"
check "codex config written" [ -f "$CT" ]
check "codex config is valid TOML" toml_ok "$CT"
check "codex config enables plugin-a" grep -qx '\[plugins."plugin-a@example-market"\]' "$CT"
check "codex config enables plugin-b" grep -qx '\[plugins."plugin-b@example-market"\]' "$CT"
check "codex config: no MCP server or hook table" sh -c "! grep -qE '^\[(mcp_servers|hooks)' '$CT'"
check "codex config: no drift line on a fresh home" sh -c "! (cd '$R' && scripts/checks/run 2>&1) | grep -q 'drift'"
R8="$W/home8"; mkdir -p "$R8/.claude" "$R8/.codex"; cp -R "$SRC/scripts" "$SRC/templates" "$R8/"; cp "$R/CLAUDE.md" "$R8/CLAUDE.md"
git -C "$R8" init -q
jq -n '{extraKnownMarketplaces: {"example-market": {source: {source: "github", repo: "example-org/market"}}}}' > "$R8/.claude/settings.json"
printf '[features]\nexample_flag = true\n\n[plugins."plugin-b@example-market"]\nenabled = false\n' > "$R8/.codex/config.toml"
"$R8/scripts/configure" --answers "$W/answers.codex" >/dev/null 2>&1
sed 's/^plugins=.*/plugins=plugin-a@example-market, plugin-b@example-market/' "$W/answers.codex" > "$W/answers.plug"
"$R8/scripts/configure" --answers "$W/answers.plug" >/dev/null 2>&1; rc=$?
CT8="$R8/.codex/config.toml"
check "codex config with own lines: exit 0" [ "$rc" = 0 ]
check "codex config with own lines: valid TOML" toml_ok "$CT8"
check "codex config keeps the owner's lines" grep -qx 'example_flag = true' "$CT8"
check "codex config: the owner's table is not written twice" [ "$(grep -cx '\[plugins."plugin-b@example-market"\]' "$CT8")" = 1 ]
check "codex config: marketplace source from settings.json" grep -qx 'source = "https://github.com/example-org/market.git"' "$CT8"
c8=$(shasum "$CT8"); "$R8/scripts/configure" --answers "$W/answers.plug" >/dev/null 2>&1
check "codex config: second run changes nothing" [ "$(shasum "$CT8")" = "$c8" ]
{ printf '[plugins."plugin-c@example-market"]\nenabled = true\n\n'; cat "$CT"; } > "$CT.new" && mv "$CT.new" "$CT"
dout=$(cd "$R" && scripts/checks/run 2>&1); rc=$?
check "drift: a plugin enabled for Codex only is reported" grep -q 'drift: plugin enabled for Codex only (.codex/config.toml): plugin-c@example-market' <<<"$dout"
check "drift: reported only, checks still pass" [ "$rc" = 0 ]

# 14. a Codex user gets the one-time Codex steps; a Claude user does not
cout=$("$R8/scripts/configure" --answers "$W/answers.plug" 2>&1)
check "codex steps: trust the folder" grep -q '^codex: accept the trust question' <<<"$cout"
check "codex steps: trust the hooks with /hooks" grep -q '^codex: in Codex, run /hooks once' <<<"$cout"
check "codex steps: one plugin add line per plugin" [ "$(grep -c '^codex: cd .* && codex plugin add plugin-[ab]@example-market$' <<<"$cout")" = 2 ]
cout=$("$R/scripts/configure" --answers "$A" 2>&1)
check "no codex steps for a Claude user" sh -c "! grep -q '^codex:' <<'X'
$cout
X"

# 15. terminal helpers: a Codex orchestrator runs with them off; a Claude one keeps on (device check stubbed to pass)
mkdir -p "$W/mac"; printf '#!/bin/sh\necho Darwin\n' > "$W/mac/uname"; printf '#!/bin/sh\necho ok\n' > "$W/mac/osascript"; chmod +x "$W/mac/uname" "$W/mac/osascript"
sed -e 's/^terminal_helpers=.*/terminal_helpers=on/' -e 's/^launch.command=.*/launch.command=claude/' "$W/answers.codex" > "$W/answers.hon"
PATH="$W/mac:$PATH" "$R2/scripts/configure" --answers "$W/answers.hon" >/dev/null 2>&1
check "helpers on, Claude orchestrator: config on" grep -qx 'terminal_helpers=on' "$R2/.local/config"
sed -e 's/^terminal_helpers=.*/terminal_helpers=on/' "$W/answers.codex" > "$W/answers.hcx"
out=$(PATH="$W/mac:$PATH" "$R2/scripts/configure" --answers "$W/answers.hcx" 2>&1)
check "helpers on, Codex orchestrator: config off" grep -qx 'terminal_helpers=off' "$R2/.local/config"
check "helpers on, Codex orchestrator: answers off" [ "$(grep '^terminal_helpers=' "$W/answers.hcx")" = terminal_helpers=off ]
check "helpers on, Codex orchestrator: reason reported" grep -q 'Claude Code tabs only' <<<"$out"

echo "configure.test: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
