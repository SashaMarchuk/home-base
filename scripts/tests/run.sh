#!/usr/bin/env bash
# Runs every test of the home scripts. No network: gh is the stub in tests/stubs.
# Each rule has a fixture that must pass and one that must fail. Fake personal
# values are assembled at run time and never stored in a file.
#   scripts/tests/run.sh            all tests
#   scripts/tests/run.sh <name>...  only the named groups
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/home-tests.XXXXXX")
trap 'rm -rf "$T"' EXIT
PASS=0; FAILN=0
ok() { PASS=$((PASS + 1)); }
bad() { FAILN=$((FAILN + 1)); echo "FAIL: $*"; }
expect() { # expect <description> <expected-exit> <cmd...>
  local d=$1 want=$2; shift 2
  "$@" >"$T/out" 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$d (exit $got, want $want)"; sed -n '1,8p' "$T/out" | sed 's/^/    /'; fi
}
SELECTED="$*"
sel() { [ -z "$SELECTED" ] && return 0; local g; for g in $SELECTED; do [ "$g" = "$1" ] && return 0; done; return 1; }

# Fake values (assembled, never stored).
CARD="4111""1111""1111""1111"
PHONE="+44 20""79 46 0""958"
IBAN="GB82WEST""12345698765432"
DOC="passport AB12""3456"
LUHNID="00005498-0000""-4000-8000-""00000ed31993"   # a session id whose digits pass the card check

# A scratch home: a copy of the scripts plus a config, in its own git repo.
mkhome() { # mkhome <dir> [repo]
  mkdir -p "$1"; cp -R "$SRC/scripts" "$1/"; cp "$SRC/base.manifest" "$1/" 2>/dev/null
  ( cd "$1" && git init -q -b main && printf '.local/\nscratch/\n' > .gitignore && mkdir -p .local )
  printf 'repo=%s\nlabels.needs_owner=needs-test\n' "${2:-test/home}" > "$1/home.config"
}
export PATH="$SRC/scripts/tests/stubs:$PATH" GH_STUB_DIR="$T/ghstore" HOME_LOG_SETTLE=0
unset CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID GH_CONFIG_DIR
mkdir -p "$GH_STUB_DIR"

# ---------------------------------------------------------------- config
if sel config; then
  H="$T/cfg"; mkhome "$H"
  printf 'a=1\nb = two words  # comment\n# c=3\npath=~/x\nguard.extra=foo\n' >> "$H/home.config"
  printf 'a=2\nguard.extra=bar\n' > "$H/.local/config"
  r=$(HOME_ROOT=$H bash -c '. "$0"; echo "$(cfg a)|$(cfg b)|$(cfg c dflt)|$(cfg path)|$(cfg_all guard.extra | tr "\n" ,)"' "$H/scripts/lib/config")
  [ "$r" = "2|two words|dflt|$HOME/x|foo,bar," ] && ok || bad "config reader: got '$r'"
fi

# ---------------------------------------------------------------- sensitive patterns
if sel patterns; then
  SP="$SRC/scripts/lib/sensitive-patterns"
  for v in "card $CARD" "phone $PHONE" "iban $IBAN" "$DOC" "key gh""p_$(printf 'a%.0s' $(seq 36))"; do
    expect "pattern must hit: ${v%% *}" 1 sh -c 'printf "%s\n" "$1" | "$2"' _ "$v" "$SP"
  done
  for v in "https://drive.google.com/drive/folders/EXAMPLE-FOLDER-ID" "task id x9y8z7 and a table row | notes/a.md | wiki/a.md |" \
           "build 4111 done in 12 steps" "sha 4b825dc642cb6eb9a060e54bf8d69288fbee4904" \
           "passport number: present in source, value hidden"; do
    expect "pattern must pass: $v" 0 sh -c 'printf "%s\n" "$1" | "$2"' _ "$v" "$SP"
  done
  printf 'secret-literal-value\n' > "$T/pv"
  expect "private literal must hit" 1 sh -c 'printf "x Secret-Literal-Value y\n" | "$1" --private "$2"' _ "$SP" "$T/pv"
  printf 'w:ab\nn:alphabeta\nr:\\p{Greek}\n' > "$T/terms"
  expect "term w: whole word must hit" 1 sh -c 'printf "the AB team\n" | "$1" --terms "$2"' _ "$SP" "$T/terms"
  expect "term w: must not hit inside a word" 0 sh -c 'printf "label tab abc\n" | "$1" --terms "$2"' _ "$SP" "$T/terms"
  expect "term n: normalised must hit" 1 sh -c 'printf "Alpha-Beta repo\n" | "$1" --terms "$2"' _ "$SP" "$T/terms"
  expect "term r: Greek must hit" 1 sh -c 'printf "\316\261\316\262\n" | "$1" --terms "$2"' _ "$SP" "$T/terms"
  printf 'f.md\tthe AB team\tfalse hit, generic\n' > "$T/allow"
  ( cd "$T" && printf 'the AB team\n' > f.md )
  expect "allow-list exact string suppresses" 0 sh -c 'cd "$3" && "$1" --terms "$2" --allow allow f.md' _ "$SP" "$T/terms" "$T"
fi

# ---------------------------------------------------------------- home-log
if sel home-log; then
  H="$T/hl"; mkhome "$H" test/hl; HL="$H/scripts/home-log"
  n=$("$HL" new --title "Task one" --body "Do the thing." --ready)
  [ "$n" = 1 ] && ok || bad "home-log new printed '$n'"
  n2=$("$HL" new --title "Task one" --body "Again." --ready 2>/dev/null)
  [ "$n2" = 1 ] && [ "$(gh api repos/test/hl/issues?state=all --jq length)" = 1 ] && ok || bad "new twice with the same title must not duplicate (got $n2)"
  expect "new refuses a personal value" 4 "$HL" new --title "x" --body "call $PHONE"
  expect "start" 0 "$HL" start 1 --run-id r1
  expect "start again, same run: no-op" 0 "$HL" start 1 --run-id r1
  expect "start by another run fails" 3 "$HL" start 1 --run-id r2
  expect "checkpoint with question" 0 "$HL" checkpoint 1 --run-id r1 --text "Half." --question "A or B?"
  gh api repos/test/hl/issues/1 --jq '[.labels[].name]|sort|join(",")' > "$T/l"
  [ "$(cat "$T/l")" = "needs-test,status:claimed" ] && ok || bad "labels after question: $(cat "$T/l")"
  expect "checkpoint refuses a personal value" 4 "$HL" checkpoint 1 --run-id r1 --text "card $CARD"
  expect "park" 0 "$HL" checkpoint 1 --run-id r1 --park
  [ ! -f "$H/.local/runs/1" ] && ok || bad "park must end the run"
  expect "resume parked run" 0 "$HL" start 1 --run-id r1
  expect "finish" 0 "$HL" finish 1 --run-id r1 --text "Done."
  expect "finish again: same result" 0 "$HL" finish 1 --run-id r1
  expect "finish by another run refused" 5 "$HL" finish 1 --run-id r9
  c=$(gh api repos/test/hl/issues/1/comments --jq 'length'); s=$(gh api repos/test/hl/issues/1 --jq .state)
  [ "$c" = 1 ] && [ "$s" = closed ] && ok || bad "one comment per run and closed (comments=$c state=$s)"
  # claim race: two runs at once, exactly one wins and one comment remains
  "$HL" new --title "Race" --body "r" --ready >/dev/null
  ( HOME_LOG_SETTLE=1 "$HL" start 2 --run-id ra >/dev/null 2>&1; echo $? > "$T/ra" ) &
  ( HOME_LOG_SETTLE=1 "$HL" start 2 --run-id rb >/dev/null 2>&1; echo $? > "$T/rb" ) &
  wait
  w=$(cat "$T/ra" "$T/rb" | sort | tr '\n' ' '); c=$(gh api repos/test/hl/issues/2/comments --jq 'length')
  [ "$w" = "0 3 " ] && [ "$c" = 1 ] && ok || bad "claim race: exits '$w', comments $c"
  [ "$(sed -n 's/^run=//p' "$H/.local/runs/2" 2>/dev/null)" = "$(gh api repos/test/hl/issues/2/comments --jq '.[0].body' | sed -n 's/^- run: //p')" ] && ok || bad "claim race: the winner's run file must survive"
  expect "finish by another run while a claim is active is refused" 3 "$HL" finish 2 --run-id intruder
  expect "checkpoint after finish is refused" 5 "$HL" checkpoint 1 --run-id r1 --text "late"
  "$HL" new --title "Identity" --body "i" --ready >/dev/null
  "$HL" start 3 --run-id stored-x >/dev/null
  expect "later verbs use the stored run, not the session id" 0 env CLAUDE_CODE_SESSION_ID=other-session "$HL" checkpoint 3 --text "ok"
  before=$(gh api repos/test/hl/issues/3/comments --jq length)
  expect "a failed comment read stops finish (exit 6)" 6 env GH_STUB_FAIL_MATCH='issues/3/comments' "$HL" finish 3 --text "x"
  [ "$(gh api repos/test/hl/issues/3/comments --jq length)" = "$before" ] && ok || bad "a failed read must not post a comment"
  "$HL" finish 3 >/dev/null
  # delegation and repair path
  "$HL" new --title "Parent" --body "p" --ready >/dev/null
  "$HL" start 4 --run-id p1 >/dev/null
  expect "delegate" 0 "$HL" checkpoint 4 --run-id p1 --delegated "test/child#7"
  gh api repos/test/hl/issues/4 --jq '[.labels[].name]|join(",")' | grep -qx 'status:delegated' && ok || bad "delegated label"
  expect "parent final by a new run" 0 "$HL" finish 4 --run-id orch --text "Child closed."
  # session-end stub
  "$HL" new --title "Dies" --body "d" --ready >/dev/null
  "$HL" start 5 --run-id sess-x >/dev/null
  "$HL" checkpoint 5 --run-id sess-x --text "Halfway there." --question "Which region?" >/dev/null
  echo '{"session_id":"sess-x","cwd":"/x"}' | "$H/scripts/hooks/session-end"
  body5=$(gh api repos/test/hl/issues/5/comments --jq '.[0].body')
  printf '%s\n' "$body5" | grep -qx 'Halfway there.' && printf '%s\n' "$body5" | grep -qx 'Session ended without a final summary.' \
    && printf '%s\n' "$body5" | grep -qx -- '- Open question for the owner: Which region?' && ok || bad "stub must keep the text and question and add the stub line"
  gh api repos/test/hl/issues/5/comments --jq '.[0].body' | head -1 | grep -q 'state=stub' && ok || bad "session-end must write a stub"
  gh api repos/test/hl/issues/5 --jq '[.labels[].name]|index("needs-summary")' | grep -qv null && ok || bad "session-end must add needs-summary"
  echo '{"session_id":"other"}' | "$H/scripts/hooks/session-end"; ok
  "$HL" new --title "Dies in codex" --body "d" --ready >/dev/null
  "$HL" start 6 --run-id codex-x >/dev/null
  echo '{}' | env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID=codex-x "$H/scripts/hooks/session-end"
  gh api repos/test/hl/issues/6/comments --jq '.[0].body' | grep -q 'codex resume codex-x' && ok || bad "session-end in codex must write a codex resume command"
  # new --start: opens and claims in one call; stdout is only the number
  n7=$("$HL" new --title "One call" --body "b" --start --run-id s7 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && [ "$n7" = 7 ] && ok || bad "new --start must exit 0 and print only the number (rc=$rc out='$n7')"
  [ "$(gh api repos/test/hl/issues/7 --jq '[.labels[].name]|join(",")')" = status:claimed ] && ok || bad "new --start must leave status:claimed"
  gh api repos/test/hl/issues/7/comments --jq '.[0].body' | head -1 | grep -qx '<!-- home-log run=s7 state=active -->' && ok || bad "new --start must post this run's active comment"
  [ "$(sed -n 's/^run=//p' "$H/.local/runs/7" 2>/dev/null)" = s7 ] && ok || bad "new --start must record the run file"
  n7b=$("$HL" new --title "One call" --body "b" --start 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && [ "$n7b" = 7 ] && [ "$(gh api repos/test/hl/issues/7/comments --jq length)" = 1 ] && ok || bad "new --start again (stored run) must reuse the issue and the comment (rc=$rc out='$n7b')"
  n7c=$("$HL" new --title "One call" --body "b" --start --run-id intruder 2>/dev/null); rc=$?
  [ "$rc" = 3 ] && [ "$n7c" = 7 ] && [ "$(gh api repos/test/hl/issues/7/comments --jq length)" = 1 ] && ok || bad "new --start on an issue another run holds must print the number and exit 3 (rc=$rc out='$n7c')"
  echo '{"session_id":"s7","cwd":"/x"}' | "$H/scripts/hooks/session-end"
  gh api repos/test/hl/issues/7/comments --jq '.[0].body' | head -1 | grep -q 'state=stub' && ok || bad "a forgotten finish after new --start must become a stub"
  expect "new --start refuses --ready" 2 "$HL" new --title "x2" --body "b" --start --ready
  expect "new --start refuses --status" 2 "$HL" new --title "x2" --body "b" --start --status inbox
  expect "new --start refuses the dreams label" 2 "$HL" new --title "x2" --body "b" --start --label dreams
  expect "start refuses --start" 2 "$HL" start 7 --start
  "$HL" new --title "Plain new" --body "b" >/dev/null
  [ "$(gh api repos/test/hl/issues/8/comments --jq length)" = 0 ] && [ "$(gh api repos/test/hl/issues/8 --jq '[.labels[].name]|join(",")')" = status:inbox ] && [ ! -f "$H/.local/runs/8" ] \
    && ok || bad "plain new must stay status:inbox with no comment and no run file"
  # checkpoint --handed: the parent records the hand-off without a claim; the worker's start still claims
  "$HL" new --title "Handed" --body "b" --ready >/dev/null
  expect "checkpoint without a claim still refused" 2 "$HL" checkpoint 9 --run-id par --text "x"
  expect "checkpoint --handed with no claim" 0 "$HL" checkpoint 9 --run-id par --handed $LUHNID --text "Handed to a worker."
  b9=$(gh api repos/test/hl/issues/9/comments --jq '.[0].body')
  printf '%s\n' "$b9" | head -1 | grep -qx '<!-- home-log run=par state=delegated -->' && printf '%s\n' "$b9" | grep -qx -- "- handed: $LUHNID" \
    && ! printf '%s\n' "$b9" | grep -q '^- delegated:' && ok || bad "--handed must write a delegated comment with the id in its own field: $b9"
  [ "$(gh api repos/test/hl/issues/9 --jq '[.labels[].name]|join(",")')" = status:ready ] && [ ! -f "$H/.local/runs/9" ] && ok || bad "--handed must change no label and record no run"
  expect "checkpoint --handed again: same comment" 0 "$HL" checkpoint 9 --run-id par --handed sess-w1
  [ "$(gh api repos/test/hl/issues/9/comments --jq length)" = 1 ] && ok || bad "--handed twice must keep one comment of the run"
  expect "the worker's start after --handed" 0 "$HL" start 9 --run-id worker1
  expect "the worker's finish after --handed" 0 "$HL" finish 9 --run-id worker1 --text "Done."
  expect "checkpoint --handed after the run ended refused" 5 "$HL" checkpoint 4 --run-id orch --handed sess-z
  expect "--handed refuses a bad id" 2 "$HL" checkpoint 9 --run-id par --handed "a b"
  expect "--handed refuses --park" 2 "$HL" checkpoint 9 --run-id par --handed sess-w1 --park
  expect "--handed refuses --delegated" 2 "$HL" checkpoint 9 --run-id par --handed sess-w1 --delegated "test/child#1"
  expect "--handed belongs to checkpoint" 2 "$HL" finish 9 --run-id par --handed sess-w1
fi

# ---------------------------------------------------------------- sweep
if sel sweep; then
  H="$T/sw"; mkhome "$H" test/sw; HL="$H/scripts/home-log"
  "$HL" new --title "closed by hand" --body "x" --ready >/dev/null
  gh api -X PATCH repos/test/sw/issues/1 -f state=closed >/dev/null
  "$HL" new --title "finished" --body "x" --ready >/dev/null
  "$HL" start 2 --run-id a >/dev/null; "$HL" finish 2 --run-id a --text ok >/dev/null
  out=$(cd "$H" && scripts/home-sweep)
  printf '%s\n' "$out" | grep -qx 'SWEEP closed-no-final test/sw#1' && ok || bad "sweep must report #1: $out"
  printf '%s\n' "$out" | grep -q '#2' && bad "sweep must not report a finished issue" || ok
  out2=$(cd "$H" && scripts/home-sweep)
  [ "$out" = "$out2" ] && ok || bad "sweep must be repeatable"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg m "$now" '[{number: 40, merged_at: $m, body: "Tidy up\n\nCloses #2 and also #1"}]' > "$GH_STUB_DIR/test__sw/pulls.json"
  out3=$(cd "$H" && scripts/home-sweep)
  printf '%s\n' "$out3" | grep -qx 'SWEEP pr-no-final test/sw#1 named by pull request #40' && ok || bad "sweep must find #n past the first line of a PR body: $out3"
  printf '%s\n' "$out3" | grep -q 'pr-no-final test/sw#2' && bad "sweep must not report a PR-named finished issue" || ok
  rm -f "$GH_STUB_DIR/test__sw/pulls.json"
  # session-start: base-ahead and drift always show, then at most 12 other lines; limits line shows the verdict.
  H="$T/ss"; mkhome "$H" test/ss
  { for i in $(seq 1 15); do echo "SWEEP stale-claim test/ss#$i silent for 9h"; done
    echo "SWEEP base-ahead test/ss base/main is 3 commits ahead"; echo "SWEEP drift test/ss scripts/"; } > "$T/sweep-lines"
  printf '#!/bin/sh\ncat "%s"\n' "$T/sweep-lines" > "$H/scripts/home-sweep"; chmod +x "$H/scripts/home-sweep"
  ss=$(echo '{}' | "$H/scripts/hooks/session-start")
  printf '%s\n' "$ss" | grep -qx 'SWEEP base-ahead test/ss base/main is 3 commits ahead' && ok || bad "session-start must show base-ahead past 12 lines: $ss"
  printf '%s\n' "$ss" | grep -qx 'SWEEP drift test/ss scripts/' && ok || bad "session-start must show drift past 12 lines"
  [ "$(printf '%s\n' "$ss" | grep -c '^SWEEP stale-claim')" = 12 ] && ok || bad "session-start must cap other sweep lines at 12"
  printf '%s\n' "$ss" | grep -qx 'limits: none (ok)' && ok || bad "session-start limits line must show the verdict: $ss"
  mkdir -p "$T/nohome/scripts" && cp -R "$SRC/scripts/." "$T/nohome/scripts/"
  expect "sweep exits 0 without home.config" 0 "$T/nohome/scripts/home-sweep"
fi

# ---------------------------------------------------------------- limits
if sel limits; then
  H="$T/lim"; mkhome "$H"
  printf '#!/bin/sh\necho "95 40 2030-01-01T00:00:00Z"\n' > "$T/reader-hi"; printf '#!/bin/sh\necho "10 20 2030-01-01T00:00:00Z"\n' > "$T/reader-lo"
  printf '#!/bin/sh\nexit 1\n' > "$T/reader-bad"; chmod +x "$T"/reader-*
  r=$("$H/scripts/limits" 2>/dev/null); [ "$r" = "ok -" ] && ok || bad "limits none: '$r'"
  printf 'limits.mode=soft\n' >> "$H/home.config"
  printf 'limits.reader=%s\n' "$T/reader-hi" > "$H/.local/config"; r=$("$H/scripts/limits" 2>/dev/null); [ "${r%% *}" = soft ] && ok || bad "soft over threshold: '$r'"
  printf 'limits.reader=%s\n' "$T/reader-lo" > "$H/.local/config"; r=$("$H/scripts/limits" 2>/dev/null); [ "${r%% *}" = ok ] && ok || bad "under threshold: '$r'"
  printf 'limits.reader=%s\n' "$T/reader-bad" > "$H/.local/config"; r=$("$H/scripts/limits" 2>/dev/null); [ "${r%% *}" = ok ] && ok || bad "broken reader must say ok: '$r'"
  printf 'limits.reader=%s\n' "$T/reader-hi" > "$H/.local/config"; printf 'mode=hard\n' > "$H/.local/limits"
  r=$("$H/scripts/limits" 2>/dev/null); [ "${r%% *}" = hard ] && ok || bad "live word wins: '$r'"
fi

# ---------------------------------------------------------------- bash guard
if sel guards; then
  H="$T/gd"; mkhome "$H"; printf 'guard.extra=docker[[:space:]]+restart\n' >> "$H/home.config"
  BG="$H/scripts/hooks/bash-guard"
  for c in 'pkill -f node' 'killall Finder' '/usr/bin/pkill x' 'bash -c "pkill x"' 'sudo -n killall x' 'xargs -I{} pkill {}' 'kill -9 $(pgrep x)' 'pgrep x | xargs kill' 'gh auth switch -u a' 'git push --force origin main' \
           'git push -f' 'gh repo delete a/b --yes' 'gh repo edit a/b --visibility public' 'gh api -X PATCH repos/a/b -f private=false' \
           'git push base main' 'docker restart web' 'kill -9 -1' 'kill 0' 'kill 1' 'kill -- -1' 'kill -TERM -4242' '/bin/kill -9 -1' 'for p in 1 2; do kill \$p; done' 'if true; then kill \$X; fi' '{ kill \$p; }'; do
    expect "bash-guard must block: $c" 2 sh -c 'jq -n --arg c "$1" "{tool_input:{command:\$c}}" | "$2"' _ "$c" "$BG"
  done
  for c in 'kill 4242' 'kill -TERM 4242' 'kill -s TERM 4242' 'kill 4242 2>&1' 'kill 4242 >/dev/null 2>&1' '/bin/kill 4242' 'kill -TERM 4242 4243' 'if true; then kill 4242; fi' 'echo kill -1' 'kill -l' 'git push origin main' 'git push --force origin feature-x' 'gh issue list' 'echo kill me' 'git push origin base-fix'; do
    expect "bash-guard must allow: $c" 0 sh -c 'jq -n --arg c "$1" "{tool_input:{command:\$c}}" | "$2"' _ "$c" "$BG"
  done
  SG="$H/scripts/hooks/sensitive-guard"
  printf 'secret-literal-value\n' > "$H/.local/pv"; printf 'guard.private_values=%s\n' "$H/.local/pv" > "$H/.local/config"
  expect "sensitive-guard blocks a new file with a card" 2 sh -c 'jq -n --arg p "$1/wiki/new.md" --arg t "card $2" "{tool_input:{file_path:\$p,content:\$t}}" | "$3"' _ "$H" "$CARD" "$SG"
  expect "sensitive-guard blocks an edit with a phone" 2 sh -c 'jq -n --arg p "$1/a.md" --arg t "call $2" "{tool_input:{file_path:\$p,new_string:\$t}}" | "$3"' _ "$H" "$PHONE" "$SG"
  expect "sensitive-guard blocks a private literal" 2 sh -c 'jq -n --arg p "$1/a.md" "{tool_input:{file_path:\$p,content:\"x secret-literal-value\"}}" | "$2"' _ "$H" "$SG"
  expect "sensitive-guard allows a Drive link" 0 sh -c 'jq -n --arg p "$1/a.md" "{tool_input:{file_path:\$p,content:\"https://drive.google.com/drive/folders/EXAMPLE-FOLDER-ID\"}}" | "$2"' _ "$H" "$SG"
  expect "sensitive-guard allows a board id" 0 sh -c 'jq -n --arg p "$1/a.md" "{tool_input:{file_path:\$p,content:\"task x9y8z7\"}}" | "$2"' _ "$H" "$SG"
  expect "sensitive-guard allows a table row with a link" 0 sh -c 'jq -n --arg p "$1/a.md" "{tool_input:{file_path:\$p,content:\"| notes/x.md | link | https://drive.google.com/file/d/EXAMPLE-FILE-ID/view |\"}}" | "$2"' _ "$H" "$SG"
  expect "sensitive-guard skips gitignored .local" 0 sh -c 'jq -n --arg p "$1/.local/x" --arg t "card $2" "{tool_input:{file_path:\$p,content:\$t}}" | "$3"' _ "$H" "$CARD" "$SG"
  expect "sensitive-guard skips files outside the repo" 0 sh -c 'jq -n --arg p "/elsewhere/x" --arg t "card $1" "{tool_input:{file_path:\$p,content:\$t}}" | "$2"' _ "$CARD" "$SG"
fi

# ---------------------------------------------------------------- checks
if sel checks; then
  H="$T/ck"; mkhome "$H"
  cp "$SRC/CLAUDE.md" "$H/CLAUDE.md"; ( cd "$H" && ln -s CLAUDE.md AGENTS.md && mkdir -p .claude/skills .agents && ln -s ../.claude/skills .agents/skills )
  ( cd "$H" && git add -A && git -c user.name=t -c user.email=test@users.noreply.github.com commit -qm init --no-verify )
  expect "checks pass on a clean home" 0 "$H/scripts/checks/run"
  ( cd "$H" && sed -i.bak '/BUFFER 2\/4/d' CLAUDE.md && rm CLAUDE.md.bak )
  expect "checks fail when a buffer line is gone" 1 "$H/scripts/checks/run"
  ( cd "$H" && git checkout -q CLAUDE.md )
  ( cd "$H" && head -c 17000 /dev/zero | tr '\0' 'x' >> CLAUDE.md )
  expect "checks fail when CLAUDE.md is above 16 KiB" 1 "$H/scripts/checks/run"
  ( cd "$H" && git checkout -q CLAUDE.md && rm AGENTS.md && ln -s "$H/CLAUDE.md" AGENTS.md )
  expect "checks fail on an absolute symlink" 1 "$H/scripts/checks/run"
  ( cd "$H" && rm AGENTS.md && ln -s CLAUDE.md AGENTS.md )
  printf '### D-1 a\n### D-1 b\n' > "$H/DECISIONS.md"; ( cd "$H" && git add DECISIONS.md )
  expect "checks fail on duplicate decision ids" 1 "$H/scripts/checks/run"
  printf '### D23 \xe2\x80\x94 a\n### D23 \xe2\x80\x94 b\n' > "$H/DECISIONS.md"; ( cd "$H" && git add DECISIONS.md )
  expect "checks fail on a duplicate id in the dash format" 1 "$H/scripts/checks/run"
  printf '### D23 \xe2\x80\x94 a\n### D24 \xe2\x80\x94 b\n' > "$H/DECISIONS.md"; ( cd "$H" && git add DECISIONS.md )
  expect "checks pass on distinct ids in the dash format" 0 "$H/scripts/checks/run"
  mkdir -p "$H/openspec"; echo x > "$H/openspec/a.md"; ( cd "$H" && git add openspec )
  expect "checks fail on a base-only path in a home" 1 "$H/scripts/checks/run"
  ( cd "$H" && git rm -rq --cached openspec && rm -rf openspec )
  printf 'note: call %s\n' "$PHONE" > "$H/note.md"; ( cd "$H" && git add note.md )
  expect "pre-commit (staged) fails on a phone number" 1 "$H/scripts/checks/run" --staged
  ( cd "$H" && git rm -q --cached note.md && rm note.md )
  expect "checks pass again after the fixes" 0 "$H/scripts/checks/run"
fi

# ---------------------------------------------------------------- facts stub (Dreams sink)
if sel facts; then
  export FACTS_STUB_LOG="$T/facts.log" FACTS_STUB_STORE="$T/facts.json"
  out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fact_propose","arguments":{"category":"Preference","key":"Favourite Colour","value":"teal","source":"test"}}}' \
    | "$SRC/scripts/tests/stubs/facts-mcp")
  pid=$(printf '%s\n' "$out" | sed -n 2p | jq -r '.result.content[0].text | fromjson | .proposal_id')
  [ -n "$pid" ] && [ "$pid" != null ] && ok || bad "facts stub: no proposal id"
  [ ! -f "$FACTS_STUB_STORE" ] && ok || bad "facts stub: propose must not save"
  call() { printf '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fact_save","arguments":{"proposal_id":"%s","confirmed":%s}}}\n' "$pid" "$1" | "$SRC/scripts/tests/stubs/facts-mcp" | jq -r '.result.content[0].text | fromjson | .saved'; }
  [ "$(call false)" = false ] && [ ! -f "$FACTS_STUB_STORE" ] && ok || bad "facts stub: unconfirmed save must not store"
  [ "$(call true)" = true ] && [ "$(jq length "$FACTS_STUB_STORE")" = 1 ] && ok || bad "facts stub: confirmed save must store once"
fi

# ---------------------------------------------------------------- other test files
for f in "$SRC"/scripts/tests/*.test.sh; do
  [ -f "$f" ] || continue
  g=$(basename "$f" .test.sh); sel "$g" || continue
  if bash "$f" > "$T/sub.out" 2>&1; then ok; else bad "$g tests"; sed -n '1,20p' "$T/sub.out" | sed 's/^/    /'; fi
done

echo "tests: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
