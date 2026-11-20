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
  for v in "https://drive.google.com/drive/folders/EXAMPLE-FOLDER-ID" "https://drive.google.com/file/d/EXAMPLE-FILE-ID/view" "task id x9y8z7 and a table row | notes/a.md | wiki/a.md |" \
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
  "$HL" new --title "x" --body "card $CARD call $PHONE" >/dev/null 2>"$T/err"; rc=$?
  [ "$rc" = 4 ] && grep -q 'card 41\*' "$T/err" && ! grep -qF "$CARD" "$T/err" && ! grep -qF "$(printf '%s' "$PHONE" | tr -cd 0-9)" "$T/err" \
    && ok || bad "new must refuse a personal value (exit 4) and print only the masked hit (rc=$rc): $(cat "$T/err")"
  expect "start" 0 "$HL" start 1 --run-id r1
  expect "start by another run fails" 3 "$HL" start 1 --run-id r2
  expect "checkpoint with question" 0 "$HL" checkpoint 1 --run-id r1 --text "Half." --question "A or B?"
  gh api repos/test/hl/issues/1 --jq '[.labels[].name]|sort|join(",")' > "$T/l"
  [ "$(cat "$T/l")" = "needs-test,status:claimed" ] && ok || bad "labels after question: $(cat "$T/l")"
  expect "checkpoint refuses a personal value" 4 "$HL" checkpoint 1 --run-id r1 --text "card $CARD"
  expect "park" 0 "$HL" checkpoint 1 --run-id r1 --park
  [ ! -f "$H/.local/runs/1" ] && ok || bad "park must end the run"
  expect "resume parked run" 0 "$HL" start 1 --run-id r1
  gh api repos/test/hl/issues/1/comments --jq '.[0].body' | head -1 | grep -qx '<!-- home-log run=r1 state=active -->' \
    && [ "$(gh api repos/test/hl/issues/1 --jq '[.labels[].name]|sort|join(",")')" = needs-test,status:claimed ] && [ -f "$H/.local/runs/1" ] \
    && ok || bad "resume must make the run's comment active again, set status:claimed and record the run"
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
  expect "start on a closed issue is refused" 2 "$HL" start 1 --run-id r3
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
  w0=$(grep -c '"-X"' "$GH_STUB_DIR/calls.log")
  echo '{"session_id":"other"}' | "$H/scripts/hooks/session-end"
  [ "$(grep -c '"-X"' "$GH_STUB_DIR/calls.log")" = "$w0" ] && ok || bad "session-end without a claim of this session must write nothing"
  # finish --release hands the issue back; finish --review leaves it open for review; a finished run cannot start again
  "$HL" new --title "Review and release" --body "d" --ready >/dev/null
  "$HL" start 6 --run-id rel1 >/dev/null; "$HL" checkpoint 6 --run-id rel1 --question "Keep it?" >/dev/null
  expect "finish --release" 0 "$HL" finish 6 --run-id rel1 --release "tab gone"
  gh api repos/test/hl/issues/6/comments --jq '.[0].body' | head -1 | grep -qx '<!-- home-log run=rel1 state=released -->' \
    && [ "$(gh api repos/test/hl/issues/6 --jq '[.labels[].name]|sort|join(",")')" = status:ready ] && [ "$(gh api repos/test/hl/issues/6 --jq .state)" = open ] \
    && ok || bad "finish --release must mark the comment released, drop the owner label and return the open issue to status:ready"
  "$HL" start 6 --run-id rv1 >/dev/null
  expect "finish --review" 0 "$HL" finish 6 --run-id rv1 --review --text "Ready for review."
  [ "$(gh api repos/test/hl/issues/6 --jq '[.labels[].name]|sort|join(",")')" = status:review ] && [ "$(gh api repos/test/hl/issues/6 --jq .state)" = open ] \
    && ok || bad "finish --review must leave the issue open with status:review"
  expect "a finished run starting again is refused" 5 "$HL" start 6 --run-id rv1
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
  # Codex's id wins over inherited Claude variables (a Codex run started from a Claude session)
  n10=$(env CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=claude-id CODEX_THREAD_ID=codex-id "$HL" new --title "From codex" --body b --start 2>/dev/null)
  b10=$(gh api repos/test/hl/issues/10/comments --jq '.[0].body')
  [ "$n10" = 10 ] && [ "$(sed -n 's/^run=//p' "$H/.local/runs/10")" = codex-id ] && printf '%s\n' "$b10" | grep -q '^- runner: .* · codex · ' \
    && printf '%s\n' "$b10" | grep -q 'codex resume codex-id' && ok || bad "CODEX_THREAD_ID must win run id and surface over Claude variables: $b10"
  n11=$(env CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=claude-id "$HL" new --title "From claude" --body b --start 2>/dev/null)
  [ "$(sed -n 's/^run=//p' "$H/.local/runs/11")" = claude-id ] && gh api repos/test/hl/issues/11/comments --jq '.[0].body' | grep -q '^- runner: .* · claude-code · ' \
    && ok || bad "without CODEX_THREAD_ID the Claude session id and surface stay"
  # session-end --surface codex returns at once with a slow gh; the stub still lands
  mkdir -p "$T/slowbin"; printf '#!/bin/sh\nsleep 2\nexec "%s/scripts/tests/stubs/gh" "$@"\n' "$SRC" > "$T/slowbin/gh"; chmod +x "$T/slowbin/gh"
  ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
  "$HL" new --title "Codex ends" --body b --start --run-id cx-12 >/dev/null 2>&1
  t0=$(ms); out=$(echo '{"session_id":"cx-12","cwd":"/x","hook_event_name":"SessionEnd"}' | PATH="$T/slowbin:$PATH" "$H/scripts/hooks/session-end" --surface codex 2>&1); t1=$(ms)
  [ $((t1 - t0)) -lt 1500 ] && [ -z "$out" ] && ok || bad "session-end --surface codex must return at once ($((t1 - t0)) ms, output '$out')"
  i=0; until gh api repos/test/hl/issues/12/comments --jq '.[0].body' | head -1 | grep -q 'state=stub' || [ $i -ge 30 ]; do sleep 1; i=$((i + 1)); done
  gh api repos/test/hl/issues/12/comments --jq '.[0].body' | grep -q 'cd /x && codex resume cx-12' && ok || bad "the detached session-end must still write the codex stub"
  "$HL" new --title "Claude ends" --body b --start --run-id cl-13 >/dev/null 2>&1
  t0=$(ms); echo '{"session_id":"cl-13","cwd":"/x"}' | PATH="$T/slowbin:$PATH" "$H/scripts/hooks/session-end" >/dev/null 2>&1; t1=$(ms)
  [ $((t1 - t0)) -ge 2000 ] && gh api repos/test/hl/issues/13/comments --jq '.[0].body' | grep -q 'claude --resume cl-13' \
    && ok || bad "session-end without --surface stays in the foreground and writes a claude resume command ($((t1 - t0)) ms)"
  # session-end --surface claude: never "codex resume" for the Claude session; a claim stored under CODEX_THREAD_ID is still found
  grep -q 'session-end --surface claude"' "$SRC/templates/settings.json" && ok || bad "Claude's SessionEnd hook must call session-end --surface claude"
  "$HL" new --title "Claude in codex shell" --body b --start --run-id cs-14 >/dev/null 2>&1
  echo '{"session_id":"cs-14","cwd":"/x"}' | env CODEX_THREAD_ID=th-x "$H/scripts/hooks/session-end" --surface claude
  gh api repos/test/hl/issues/14/comments --jq '.[0].body' | grep -q 'cd /x && claude --resume cs-14' && ok || bad "--surface claude must write claude --resume even with CODEX_THREAD_ID set"
  "$HL" new --title "Stored as codex" --body b --start --run-id th-15 >/dev/null 2>&1
  echo '{"session_id":"cs-other","cwd":"/x"}' | env CODEX_THREAD_ID=th-15 "$H/scripts/hooks/session-end" --surface claude
  gh api repos/test/hl/issues/15/comments --jq '.[0].body' | grep -q 'cd /x && codex resume th-15' && ok || bad "a claim stored under CODEX_THREAD_ID must be found and resumed with codex resume"
  "$HL" new --title "Not mine" --body b --start --run-id other-16 >/dev/null 2>&1
  echo '{"session_id":"cs-other","cwd":"/x"}' | env CODEX_THREAD_ID=th-15 "$H/scripts/hooks/session-end" --surface claude
  gh api repos/test/hl/issues/16/comments --jq '.[0].body' | head -1 | grep -q 'state=active' && ok || bad "a claim of another run must stay active"
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
  # An older hand-off (status:delegated here, the work in another home's issue) is still reported when that issue closes.
  "$HL" new --title "older hand-off" --body "x" --ready >/dev/null
  "$HL" start 3 --run-id d1 >/dev/null; "$HL" checkpoint 3 --run-id d1 --delegated "test/kid#1" >/dev/null
  gh api -X POST repos/test/kid/issues -f title=work -f body=x >/dev/null
  out4=$(cd "$H" && scripts/home-sweep)
  printf '%s\n' "$out4" | grep -q 'delegated-child-closed' && bad "sweep must not report an older hand-off whose issue is open: $out4" || ok
  gh api -X PATCH repos/test/kid/issues/1 -f state=closed >/dev/null
  out4=$(cd "$H" && scripts/home-sweep)
  printf '%s\n' "$out4" | grep -qx 'SWEEP delegated-child-closed test/sw#3 child test/kid#1' && ok || bad "sweep must report an older hand-off whose issue closed: $out4"
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

# ---------------------------------------------------------------- combined status
if sel status; then
  P="$T/st-par"; K="$T/st-kid"; mkhome "$P" test/stpar; mkhome "$K" test/stkid
  printf 'labels.needs_owner=kid-q\n' >> "$K/home.config"
  { printf 'homes.kid.repo=test/stkid\nhomes.kid.path=%s\nhomes.kid.role=child\n' "$K"
    printf 'homes.mom.repo=test/stmom\nhomes.mom.role=parent\nhomes.pal.repo=test/stpal\nhomes.pal.role=peer\n'; } >> "$P/home.config"
  mk() { gh api -X POST "repos/$1/issues" -f "title=$2" -f body=x $(shift 2; for l in "$@"; do printf -- '-f labels[]=%s ' "$l"; done) >/dev/null; }
  mk test/stpar "Plan the week" status:ready
  mk test/stkid "Pick a supplier" status:parked kid-q
  mk test/stkid "Fix the build" status:claimed
  mk test/stkid "Night summary" dreams
  mk test/stkid "Freeze f1" status:parked
  mk test/stmom "Parent work" status:claimed
  python3 -c 'import time; time.sleep(60)' status-live-marker & LIVE=$!
  jq -n --arg p "$LIVE" '[
    {session_id: "s-live", tty: "/dev/ttys101", pid: ($p|tonumber), match: "status-live-marker", issue: 2, role: "worker", closed: null},
    {session_id: "s-lost", tty: "/dev/ttys102", pid: 2147483646, match: "s-lost", issue: 3, role: "orchestrator", closed: null},
    {session_id: "s-new", tty: null, pid: null, match: "s-new", issue: null, role: "worker", closed: null},
    {session_id: "s-gone", tty: null, pid: null, match: "s-gone", issue: 5, role: "worker", closed: null, lost: "2026-01-01T00:00:00Z", lost_tty: "ttys105"},
    {session_id: "s-done", tty: "/dev/ttys104", pid: 1, match: "s-done", issue: 9, role: "worker", closed: "2026-01-01T00:00:00Z"}]' > "$K/.local/registry.json"
  before=$(wc -l < "$GH_STUB_DIR/calls.log")
  out=$("$P/scripts/home-status" --all); rc=$?
  [ "$rc" = 0 ] && ok || bad "home-status --all must exit 0 (got $rc)"
  exp="== this test/stpar (this home)
ready #1 Plan the week
sessions: none open
== kid test/stkid (child)
question #1 Pick a supplier
claimed #2 Fix the build
frozen #4 Freeze f1
session live ttys101 s-live #2 worker
session stopped? ttys102 s-lost #3 orchestrator
session starting - s-new #- worker
session lost ttys105 s-gone #5 worker
== pal test/stpal (peer)
issues: none open
sessions: unknown (no local path (homes.pal.path))"
  [ "$out" = "$exp" ] && ok || bad "home-status --all: got
$out"
  printf '%s\n' "$out" | grep -q 'mom\|Parent work' && bad "--all must not read a parent home" || ok
  tail -n +"$((before + 1))" "$GH_STUB_DIR/calls.log" | grep -qE '"(-X|--method)"' && bad "home-status must only read" || ok
  "$P/scripts/home-status" | grep -q '^== kid' && bad "without --all only this home is shown" || ok
  "$P/scripts/home-status" --home mom | grep -qx 'claimed #1 Parent work' && ok || bad "--home must read a named parent home"
  expect "--home with an unknown name" 2 "$P/scripts/home-status" --home nobody
  out=$(GH_STUB_FAIL_MATCH='test/stkid' "$P/scripts/home-status" --all)
  printf '%s\n' "$out" | grep -qx 'issues: cannot read test/stkid' && ok || bad "an unreadable repo must be named, not shown as empty: $out"
  kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
  # each home is read with its own gh config, from its own folder; never with this home's
  mkdir -p "$T/ghwrap"; printf '#!/bin/sh\necho "${GH_CONFIG_DIR:-none} $PWD $*" >> "%s/ghenv.log"\nexec "%s/scripts/tests/stubs/gh" "$@"\n' "$T" "$SRC" > "$T/ghwrap/gh"; chmod +x "$T/ghwrap/gh"
  printf 'gh.config_dir=%s/gh-par\n' "$T" > "$P/.local/config"; KP=$(cd "$K" && pwd)
  : > "$T/ghenv.log"; PATH="$T/ghwrap:$PATH" GH_CONFIG_DIR="$T/gh-inherited" "$P/scripts/home-status" --all >/dev/null
  grep -q "^$T/gh-par .* repos/test/stpar/" "$T/ghenv.log" && ok || bad "this home must be read with its own gh.config_dir: $(cat "$T/ghenv.log")"
  grep -q "^none $KP .*repos/test/stkid/" "$T/ghenv.log" && ok || bad "a related home without gh.config_dir must be read from its folder with none: $(cat "$T/ghenv.log")"
  grep -q "^none .*repos/test/stpal/" "$T/ghenv.log" && ok || bad "a related home with no clone must not get this home's gh config"
  grep -q "gh-inherited\|gh-par .*repos/test/st\(kid\|pal\)/" "$T/ghenv.log" && bad "no related home may be read with this home's or the inherited gh config" || ok
  printf 'gh.config_dir=%s/gh-kid\n' "$T" > "$K/.local/config"
  : > "$T/ghenv.log"; PATH="$T/ghwrap:$PATH" "$P/scripts/home-status" --all >/dev/null
  grep -q "^$T/gh-kid $KP .*repos/test/stkid/" "$T/ghenv.log" && ok || bad "a related home's own gh.config_dir must be used: $(cat "$T/ghenv.log")"
  rm -f "$P/.local/config" "$K/.local/config"
fi

# ---------------------------------------------------------------- voice transcript
if sel voice; then
  VC="$SRC/scripts/voice-collect"; FX="$SRC/scripts/tests/fixtures/voice-rollout.jsonl"
  out=$("$VC" "$FX" --since 2026-01-05T10:00:00Z); rc=$?
  exp='# Voice transcript

Source: voice-rollout.jsonl
Time (UTC): 2026-01-05 10:00:10 to 10:00:45
Turns: 6 (AI backchannels dropped: 2)

**[10:00:10] AI:** First question: which shelf gets the new labels?

**[10:00:15] Me:** The top shelf, the one with the jars.

**[10:00:25] Me:** And the lable maker stays in the drawer.

**[10:00:30] AI:** Noted, I will write that down. Second question: who keeps the key?

**[10:00:40] Me:** Yes.

**[10:00:45] Me:** The neighbour keeps it.'
  [ "$rc" = 0 ] && [ "$out" = "$exp" ] && ok || bad "voice-collect transcript (rc $rc):
$out"
  "$VC" "$FX" | grep -qx '\*\*\[09:59:50\] Me:\*\* A warm-up line before the interview.' && ok || bad "without --since every segment is kept"
  "$VC" "$FX" | grep -q 'Not part of the voice transcript' && bad "only transcript segments may be read" || ok
  H="$T/vc"; mkhome "$H"
  expect "voice-collect refuses an --out tracked by git" 3 "$VC" "$FX" --out "$H/wiki/call.md"
  [ ! -e "$H/wiki/call.md" ] && ok || bad "a refused --out must write nothing"
  expect "voice-collect writes into an ignored folder" 0 "$VC" "$FX" --out "$H/.local/call.md"
  printf 'old\n' > "$H/.local/kept.md"; ( cd "$H" && git add -f .local/kept.md )
  expect "voice-collect refuses a tracked file that an ignore pattern matches" 3 "$VC" "$FX" --out "$H/.local/kept.md"
  [ "$(cat "$H/.local/kept.md")" = old ] && ok || bad "a tracked file must not be written over"
  printf '%s\n' '{"ordinal":1,"type":"realtime_item","payload":{"type":"transcript_segment","role":"assistant","text":" Si."}}' \
    '{"ordinal":2,"type":"realtime_item","payload":{"type":"transcript_segment","role":"assistant","text":" Mm-hm."}}' \
    '{"ordinal":3,"type":"realtime_item","payload":{"type":"transcript_segment","role":"user","text":" Da."}}' > "$T/bc.jsonl"
  printf 'voice.backchannels=si, DA\n' > "$H/.local/config"
  out=$(HOME_ROOT="$H" "$VC" "$T/bc.jsonl")
  printf '%s\n' "$out" | grep -q '^Turns: 2 (AI backchannels dropped: 1)$' && printf '%s\n' "$out" | grep -qx '\*\*\[--:--:--\] AI:\*\* Mm-hm\.' &&
    printf '%s\n' "$out" | grep -qx '\*\*\[--:--:--\] Me:\*\* Da\.' && ok || bad "voice.backchannels must replace the default list:
$out"
  rm -f "$H/.local/config"
  mkdir -p "$T/novcs"; expect "voice-collect writes outside git" 0 "$VC" "$FX" --out "$T/novcs/call.md"
  cmp -s "$T/novcs/call.md" "$H/.local/call.md" && grep -q '^Turns: 7 ' "$T/novcs/call.md" && ok || bad "--out must hold the transcript"
  mkdir -p "$T/codex/sessions/2026/01/05" "$T/codex/sessions/2026/01/06"
  cp "$FX" "$T/codex/sessions/2026/01/05/rollout-a.jsonl"
  echo '{"type":"session_meta","payload":{}}' > "$T/codex/sessions/2026/01/06/rollout-b.jsonl"
  touch -t 202601050000 "$T/codex/sessions/2026/01/05/rollout-a.jsonl"
  CODEX_HOME="$T/codex" "$VC" --latest | grep -q '^Source: rollout-a.jsonl$' && ok || bad "--latest must pick the newest rollout that holds a transcript"
  expect "--latest with nothing after --since" 4 env CODEX_HOME="$T/codex" "$VC" --latest --since 2026-02-01T00:00:00Z
  expect "a file and --latest together" 2 "$VC" "$FX" --latest
  expect "a bad --since" 2 "$VC" "$FX" --since yesterday
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
  printf 'mode=hard\nuntil=2000-01-01T00:00:00Z\n' > "$H/.local/limits"
  r=$("$H/scripts/limits" 2>/dev/null); [ "${r%% *}" = soft ] && ok || bad "a live word whose until has passed must be ignored: '$r'"
fi

# ---------------------------------------------------------------- bash guard
if sel guards; then
  H="$T/gd"; mkhome "$H"; printf 'guard.extra=docker[[:space:]]+restart\n' >> "$H/home.config"
  BG="$H/scripts/hooks/bash-guard"
  for c in 'pkill -f node' 'killall Finder' '/usr/bin/pkill x' 'bash -c "pkill x"' 'sudo -n killall x' 'xargs -I{} pkill {}' 'kill -9 $(pgrep x)' 'pgrep x | xargs kill' 'gh auth switch -u a' 'git push --force origin main' \
           'git push -f' 'gh repo delete a/b --yes' 'gh repo edit a/b --visibility public' 'gh api -X PATCH repos/a/b -f private=false' \
           'git push base main' 'docker restart web' 'kill -9 -1' 'kill 0' 'kill 1' 'kill -- -1' 'kill -TERM -4242' '/bin/kill -9 -1' 'for p in 1 2; do kill \$p; done' 'if true; then kill \$X; fi' '{ kill \$p; }' \
           'sh -c "kill -9 -1"' 'eval "kill 0"' 'true & kill 0' 'kill -0 -1' 'kill 4242 & kill -- -1'; do
    expect "bash-guard must block: $c" 2 sh -c 'jq -n --arg c "$1" "{tool_input:{command:\$c}}" | "$2"' _ "$c" "$BG"
  done
  # the same kills behind a path, "--", a variable, quotes, a backslash, a redirection, a wrapper, a keyword or two "&"
  for c in '/bin/sh -c "kill -9 -1"' "/bin/bash -lc 'kill 0'" "bash -c -- 'kill -9 -1'" 'a & b & kill 0' 'true&kill 0' 'x&y&kill 0' 'FOO=1 kill -9 -1' '"kill" -9 -1' "'kill' 0" '\kill 0' \
           'sudo -n kill -9 -1' '>/dev/null kill 0' '/usr/bin/env kill 0' 'command -p kill 0' 'if kill 0; then :; fi' 'until kill 0; do :; done' 'echo 5 | xargs -n 1 kill' 'echo 5 | xargs -I {} /bin/kill {}'; do
    expect "bash-guard must block: $c" 2 sh -c 'jq -n --arg c "$1" "{tool_input:{command:\$c}}" | "$2"' _ "$c" "$BG"
  done
  # the word in text stays allowed, as before
  for c in 'git commit -m "kill the bug"' 'grep kill file' 'man kill' 'cat notes/kill.md' 'git checkout kill-switch' 'echo "please kill 4242 now"' 'mytool --note "kill it softly"' \
           'scripts/home-log finish 3 --text "a kill of 12 processes"' 'while kill -0 4242; do sleep 1; done' 'skill 4242' './kill.sh 4242' 'python3 -c "os.kill(4242, 9)"'; do
    expect "bash-guard must allow: $c" 0 sh -c 'jq -n --arg c "$1" "{tool_input:{command:\$c}}" | "$2"' _ "$c" "$BG"
  done
  for c in 'echo kill -1' 'kill -l' 'git push origin main' 'git push --force origin feature-x' 'gh issue list' 'echo kill me' 'git push origin base-fix' 'echo a 2>&1 &'; do
    expect "bash-guard must allow: $c" 0 sh -c 'jq -n --arg c "$1" "{tool_input:{command:\$c}}" | "$2"' _ "$c" "$BG"
  done
  # Kills of exact PIDs, on real processes. The guard runs under a process whose command is the
  # agent's name: @OWN@ and @DEEP@ are started inside it, @SELF@ is that process, @FOR@ is
  # started here, outside it.
  cat > "$T/agent.sh" <<'EOS'
#!/bin/bash
# agent.sh <hook> <command>: start a child and a grandchild, run the hook on the command, pass its output and exit code on
sleep 300 & own=$!; disown
( sleep 300 & echo $! > "$0.deep"; wait ) 2>/dev/null & disown
n=0; until [ -s "$0.deep" ] || [ $n -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
deep=$(cat "$0.deep"); rm -f "$0.deep"
c=${2//@OWN@/$own}; c=${c//@DEEP@/$deep}; c=${c//@SELF@/$$}
jq -n --arg c "$c" '{tool_name:"Bash",tool_input:{command:$c}}' | "$1"; rc=$?
kill "$own" "$deep" 2>/dev/null
exit $rc
EOS
  sleep 300 & FOR=$!; disown
  true & DEAD=$!; wait "$DEAD"
  kg() { # kg <allow|ask|block> <agent name> <command>: allow and block print nothing on stdout; ask prints the decision
    local out rc c=${3//@FOR@/$FOR}
    out=$(bash -c 'exec -a "$0" bash "$@"' "$2" "$T/agent.sh" "${GUARD:-$BG}" "$c" 2>"$T/err"); rc=$?
    case "$1" in
      allow) [ "$rc" = 0 ] && [ -z "$out" ] ;;
      ask) [ "$rc" = 0 ] && printf '%s' "$out" | jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "ask" and (.permissionDecisionReason | test("PID [0-9]+ \\("))' >/dev/null ;;
      unread) [ "$rc" = 2 ] && [ -z "$out" ] && grep -q '^bash-guard: blocked: .*cannot read.*through a file' "$T/err" ;;
      block) [ "$rc" = 2 ] && [ -z "$out" ] && grep -q '^bash-guard: blocked: ' "$T/err" ;;
    esac && ok || bad "kill guard must $1 under $2: $c (exit $rc, stdout '$out', stderr '$(head -1 "$T/err")')"
  }
  for c in 'kill @OWN@' 'kill -TERM @OWN@' 'kill -s TERM @OWN@' 'kill @OWN@ 2>&1' 'kill @OWN@ >/dev/null 2>&1' '/bin/kill @OWN@' 'kill -TERM @OWN@ @DEEP@' \
           'if true; then kill @OWN@; fi' 'bash -c "kill @OWN@"' 'true & kill @DEEP@' 'kill @OWN@ &'; do
    kg allow claude "$c"; kg allow codex "$c"
  done
  for c in 'kill @FOR@' '/bin/kill -9 @FOR@' 'kill @OWN@ @FOR@' 'sh -c "kill @FOR@"' 'echo x & kill @FOR@' 'kill @SELF@'; do
    kg ask claude "$c"; kg block codex "$c"
    GUARD="$H/scripts/hooks/codex-pre-tool" kg block claude "$c"
  done
  CODEX_THREAD_ID=t-1 kg block claude 'kill @FOR@'
  # the same kill behind a variable, a wrapper word, quotes, a backslash, a redirection, a keyword or two "&" is read as a kill
  for c in 'FOO=1 kill @FOR@' 'env FOO=1 kill @FOR@' 'command -p kill @FOR@' '\kill @FOR@' '"kill" @FOR@' '/usr/bin/env kill @FOR@' '>/dev/null kill @FOR@' 'x&y&kill @FOR@' 'if kill @FOR@; then :; fi'; do
    kg ask claude "$c"; kg block codex "$c"
  done
  for c in 'FOO=1 kill @OWN@' '"kill" @OWN@' 'if kill @OWN@; then :; fi' 'x&y&kill @OWN@'; do kg allow claude "$c"; kg allow codex "$c"; done
  # a kill the guard cannot read (another command in front, a trap, a case arm, a function body): refused on every surface, never asked, own process or not
  for c in 'timeout 5 kill @FOR@' 'nice kill -9 @FOR@' "trap 'kill @FOR@' EXIT" 'case x in x) kill @FOR@;; esac' 'f() { kill @FOR@; }; f' 'sudo -u x kill @FOR@' 'timeout 5 kill @OWN@' 'mytool --note "we kill 12 of them"' 'ls | xargs grep kill'; do
    kg unread claude "$c"; kg block codex "$c"
    GUARD="$H/scripts/hooks/codex-pre-tool" kg block claude "$c"
  done
  kg block claude 'timeout 5 kill @FOR@; gh auth switch'
  out=$(bash -c 'exec -a claude bash "$@"' _ "$T/agent.sh" "$BG" "kill $FOR" 2>/dev/null)
  printf '%s' "$out" | jq -e --arg p "PID $FOR (sleep 300)" '.hookSpecificOutput.permissionDecisionReason | contains($p)' >/dev/null && ok || bad "the ask reason must name the PID and its command: $out"
  kg block claude 'kill @FOR@; gh auth switch'; kg block claude 'kill @FOR@ && docker restart web'
  for c in 'kill -0 @FOR@' 'kill -s 0 @FOR@' 'kill -n 0 @FOR@' 'kill -0 @FOR@ && echo alive'; do kg allow claude "$c"; kg allow codex "$c"; done
  kg block claude "kill $DEAD"
  mkdir -p "$T/nops"; printf '#!/bin/sh\nexit 1\n' > "$T/nops/ps"; chmod +x "$T/nops/ps"
  PATH="$T/nops:$PATH" kg block claude 'kill @OWN@'
  # an option after a PID makes no probe: the shell stops reading options at the first PID
  for c in 'kill @FOR@ -l' 'kill @FOR@ -0' 'kill @FOR@ -s 0' 'kill -9 -l @FOR@' 'kill @OWN@ -0' 'kill @OWN@ -4242'; do kg block claude "$c"; done
  # no agent process above the hook: its parent exits at once, so the hook hangs under PID 1
  jq -n --arg c "kill $FOR" '{tool_name:"Bash",tool_input:{command:$c}}' > "$T/orph.json"; rm -f "$T/orph.rc"
  bash -c '( sleep 0.5; "$1" < "$2" > "$3" 2>&1; echo $? > "$4" ) >/dev/null 2>&1 &' _ "$BG" "$T/orph.json" "$T/orph.out" "$T/orph.rc"
  n=0; until [ -s "$T/orph.rc" ] || [ $n -ge 100 ]; do sleep 0.1; n=$((n + 1)); done
  [ "$(cat "$T/orph.rc" 2>/dev/null)" = 2 ] && grep -q 'no agent process above this hook' "$T/orph.out" && ok || bad "kill guard must refuse with no agent process above it (exit $(cat "$T/orph.rc" 2>/dev/null): $(head -1 "$T/orph.out" 2>/dev/null))"
  # The registry vouches for a PID only while its entry is open, not adopted, and its tty and match fit the live process.
  FTTY=$(ps -o tty= -p "$FOR" | tr -d ' ')
  reg() { # reg <tty> <match> [<extra fields>]
    jq -n --argjson p "$FOR" --arg t "$1" --arg m "$2" --argjson x "${3:-null}" \
      '[{session_id: "s-old", pid: 1, tty: $t, match: $m, closed: null}, ({session_id: "s-1", pid: $p, tty: $t, match: $m, closed: null} + $x)]' > "$H/.local/registry.json"; }
  reg "$FTTY" "sleep 300"; kg allow claude 'kill @FOR@'; kg allow codex 'kill @FOR@'; kg allow claude 'kill @OWN@ @FOR@'
  reg "$FTTY" "another-command"; kg ask claude 'kill @FOR@'; kg block codex 'kill @FOR@'
  reg "ttys999" "sleep 300"; kg ask claude 'kill @FOR@'
  reg "$FTTY" ""; kg ask claude 'kill @FOR@'
  reg "$FTTY" "sleep 300" '{"closed":"2030-01-01T00:00:00Z"}'; kg ask claude 'kill @FOR@'
  reg "$FTTY" "sleep 300" '{"adopted":true}'; kg ask claude 'kill @FOR@'
  for r in '[{' '{"pid":1}'; do
    printf '%s\n' "$r" > "$H/.local/registry.json"; kg block claude 'kill @FOR@'; kg allow claude 'kill @OWN@'
  done
  rm -f "$H/.local/registry.json"
  kill "$FOR"
  SG="$H/scripts/hooks/sensitive-guard"
  printf 'secret-literal-value\n' > "$H/.local/pv"; printf 'guard.private_values=%s\n' "$H/.local/pv" > "$H/.local/config"
  expect "sensitive-guard blocks a new file with a card" 2 sh -c 'jq -n --arg p "$1/wiki/new.md" --arg t "card $2" "{tool_input:{file_path:\$p,content:\$t}}" | "$3"' _ "$H" "$CARD" "$SG"
  expect "sensitive-guard blocks an edit with a phone" 2 sh -c 'jq -n --arg p "$1/a.md" --arg t "call $2" "{tool_input:{file_path:\$p,new_string:\$t}}" | "$3"' _ "$H" "$PHONE" "$SG"
  expect "sensitive-guard blocks a multi-edit with a card" 2 sh -c 'jq -n --arg p "$1/a.md" --arg t "card $2" "{tool_input:{file_path:\$p,edits:[{old_string:\"a\",new_string:\"b\"},{old_string:\"c\",new_string:\$t}]}}" | "$3"' _ "$H" "$CARD" "$SG"
  expect "sensitive-guard blocks a private literal" 2 sh -c 'jq -n --arg p "$1/a.md" "{tool_input:{file_path:\$p,content:\"x secret-literal-value\"}}" | "$2"' _ "$H" "$SG"
  expect "sensitive-guard allows a Drive link" 0 sh -c 'jq -n --arg p "$1/a.md" "{tool_input:{file_path:\$p,content:\"https://drive.google.com/drive/folders/EXAMPLE-FOLDER-ID\"}}" | "$2"' _ "$H" "$SG"
  expect "sensitive-guard skips gitignored .local" 0 sh -c 'jq -n --arg p "$1/.local/x" --arg t "card $2" "{tool_input:{file_path:\$p,content:\$t}}" | "$3"' _ "$H" "$CARD" "$SG"
  expect "sensitive-guard skips files outside the repo" 0 sh -c 'jq -n --arg p "/elsewhere/x" --arg t "card $1" "{tool_input:{file_path:\$p,content:\$t}}" | "$2"' _ "$CARD" "$SG"
  # Codex apply_patch: the captured shape (whole patch in tool_input.command, absolute paths, no file_path).
  ap() { # ap <cwd> <patch>: a Codex apply_patch payload
    jq -n --arg c "$2" --arg d "$1" '{session_id:"s-1",cwd:$d,model:"m",source:"cli",hook_event_name:"PreToolUse",tool_name:"apply_patch",tool_input:{command:$c}}'; }
  P_ADD=$(printf '*** Begin Patch\n*** Add File: %s/wiki/pay.md\n+# Payments\n+card %s\n*** End Patch' "$H" "$CARD")
  P_CLEAN=$(printf '*** Begin Patch\n*** Add File: %s/wiki/ok.md\n+# Notes\n+see https://drive.google.com/drive/folders/EXAMPLE-FOLDER-ID\n*** End Patch' "$H")
  P_UPD=$(printf '*** Begin Patch\n*** Update File: wiki/a.md\n@@\n-old line\n+call %s\n*** End Patch' "$PHONE")
  P_DEL=$(printf '*** Begin Patch\n*** Update File: wiki/a.md\n@@\n-card %s\n+removed\n*** End Patch' "$CARD")
  P_MOVE=$(printf '*** Begin Patch\n*** Update File: %s/.local/x.md\n*** Move to: %s/wiki/moved.md\n@@\n+card %s\n*** End Patch' "$H" "$H" "$CARD")
  P_TWO=$(printf '*** Begin Patch\n*** Add File: %s/.local/n.md\n+card %s\n*** Add File: %s/wiki/b.md\n+card %s\n*** End Patch' "$H" "$CARD" "$H" "$CARD")
  P_LOCAL=$(printf '*** Begin Patch\n*** Add File: %s/.local/n.md\n+card %s\n*** End Patch' "$H" "$CARD")
  printf 'card %s\n' "$CARD" > "$H/.local/secret.md"; printf 'plain notes\n' > "$H/.local/clean.md"
  P_MV0=$(printf '*** Begin Patch\n*** Update File: %s/.local/secret.md\n*** Move to: %s/wiki/s.md\n*** End Patch' "$H" "$H")
  P_MVC=$(printf '*** Begin Patch\n*** Update File: .local/secret.md\n*** Move to: wiki/s.md\n@@\n card\n*** End Patch')
  P_MVOK=$(printf '*** Begin Patch\n*** Update File: %s/.local/clean.md\n*** Move to: %s/wiki/c.md\n*** End Patch' "$H" "$H")
  P_IND=$(printf '*** Begin Patch\n  *** Add File:   %s/wiki/i.md  \n+card %s\n*** End Patch' "$H" "$CARD")
  P_INDOK=$(printf '*** Begin Patch\n  *** Add File:   %s/wiki/i.md  \n+plain notes\n*** End Patch' "$H")
  for c in ADD UPD MOVE TWO MV0 MVC IND; do
    eval "pt=\$P_$c"
    ap "$H" "$pt" > "$T/ap.json"
    expect "sensitive-guard blocks apply_patch ($c)" 2 sh -c '"$1" < "$2"' _ "$SG" "$T/ap.json"
  done
  for c in CLEAN DEL LOCAL MVOK INDOK; do
    eval "pt=\$P_$c"
    ap "$H" "$pt" > "$T/ap.json"
    expect "sensitive-guard allows apply_patch ($c)" 0 sh -c '"$1" < "$2"' _ "$SG" "$T/ap.json"
  done
  # bash-guard: the Codex exec_command shape (.tool_input.cmd, a string or a list of words)
  expect "bash-guard blocks .cmd list: gh auth switch" 2 sh -c 'jq -n "{tool_name:\"exec_command\",tool_input:{cmd:[\"gh\",\"auth\",\"switch\"]}}" | "$1"' _ "$BG"
  expect "bash-guard blocks .cmd list: bash -lc gh auth switch" 2 sh -c 'jq -n "{tool_name:\"exec_command\",tool_input:{cmd:[\"/bin/bash\",\"-lc\",\"gh auth switch -u a\"]}}" | "$1"' _ "$BG"
  expect "bash-guard blocks .cmd list: bash -e -c kill -9 -1" 2 sh -c 'jq -n "{tool_name:\"exec_command\",tool_input:{cmd:[\"bash\",\"-e\",\"-c\",\"kill -9 -1\"]}}" | "$1"' _ "$BG"
  expect "bash-guard allows .cmd list: bash -e -c kill -0 4242" 0 sh -c 'jq -n "{tool_name:\"exec_command\",tool_input:{cmd:[\"bash\",\"-e\",\"-c\",\"kill -0 4242\"]}}" | "$1"' _ "$BG"
  expect "bash-guard allows .cmd list: bash -lc gh issue list" 0 sh -c 'jq -n "{tool_name:\"exec_command\",tool_input:{cmd:[\"bash\",\"-lc\",\"gh issue list\"]}}" | "$1"' _ "$BG"
  expect "bash-guard allows .cmd: gh issue list" 0 sh -c 'jq -n "{tool_name:\"exec_command\",tool_input:{cmd:\"gh issue list\"}}" | "$1"' _ "$BG"
  # Codex hooks: each command exactly as .codex/hooks.json writes it, run from a subfolder of the home.
  cp -R "$SRC/.codex" "$H/"; mkdir -p "$H/wiki/sub"
  HJ="$H/.codex/hooks.json"
  [ "$(jq -r '.hooks.PreToolUse | map(.matcher) | join(",")' "$HJ")" = '.*' ] && ok || bad "Codex PreToolUse matcher must be .* (every tool reaches the dispatcher)"
  PRE=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HJ")
  hook() { # hook <payload file>: the PreToolUse command run as Codex runs it
    ( cd "$H/wiki/sub" && sh -c "$PRE" < "$1" ); }
  jq -n '{tool_name:"Bash",tool_input:{command:"gh auth switch -u a"}}' > "$T/p1.json"
  jq -n '{tool_name:"exec_command",tool_input:{cmd:"gh auth switch -u a"}}' > "$T/p2.json"
  jq -n '{tool_name:"Bash",tool_input:{command:"gh issue list"}}' > "$T/p3.json"
  jq -n '{tool_name:"mcp__notes__run",tool_input:{command:"gh auth switch -u a"}}' > "$T/p4.json"
  ap "$H" "$(printf '*** Begin Patch\n*** Add File: %s/wiki/howto.md\n+Never run pkill -f node here.\n*** End Patch' "$H")" > "$T/p5.json"
  ap "$H" "$P_ADD" > "$T/p6.json"
  jq -n '{tool_name:"shell",tool_input:{command:["bash","-lc","pkill -f node"]}}' > "$T/p9.json"
  jq -n '{tool_name:"local_shell",tool_input:{command:["gh","auth","switch","-u","a"]}}' > "$T/p10.json"
  expect "Codex hook blocks Bash: gh auth switch" 2 hook "$T/p1.json"
  expect "Codex hook blocks exec_command: gh auth switch" 2 hook "$T/p2.json"
  expect "Codex hook blocks shell: pkill" 2 hook "$T/p9.json"
  expect "Codex hook blocks local_shell: gh auth switch" 2 hook "$T/p10.json"
  expect "Codex hook allows a clean command" 0 hook "$T/p3.json"
  expect "Codex hook passes another tool untouched" 0 hook "$T/p4.json"
  expect "Codex hook never sends a patch to bash-guard" 0 hook "$T/p5.json"
  expect "Codex hook blocks apply_patch with a card" 2 hook "$T/p6.json"
  jq -n --arg c "$(printf "apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: wiki/h.md\n+card %s\n*** End Patch\nEOF" "$CARD")" --arg d "$H" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' > "$T/p7.json"
  jq -n --arg c "$(printf "apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: wiki/h.md\n+plain notes\n*** End Patch\nEOF")" --arg d "$H" '{tool_name:"exec_command",cwd:$d,tool_input:{cmd:$c}}' > "$T/p8.json"
  expect "Codex hook blocks a shell heredoc apply_patch with a card" 2 hook "$T/p7.json"
  expect "Codex hook allows a clean shell heredoc apply_patch" 0 hook "$T/p8.json"
  for ev in SessionStart SessionEnd; do
    c=$(jq -r --arg e "$ev" '.hooks[$e][0].hooks[0].command' "$HJ")
    f=$(cd "$H/wiki/sub" && sh -c "printf '%s\n' $c" | head -1)
    [ -x "$f" ] && ok || bad "Codex $ev hook command must name an executable script ($f)"
  done
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
  printf 'note\n' > "$H/note.md"; ( cd "$H" && git add note.md ); printf 'note: call %s\n' "$PHONE" > "$H/note.md"
  expect "pre-commit (staged) checks the index: a phone only in the working tree passes" 0 "$H/scripts/checks/run" --staged
  ( cd "$H" && git add note.md ); printf 'note\n' > "$H/note.md"
  expect "pre-commit (staged) fails on a phone number only in the index" 1 "$H/scripts/checks/run" --staged
  ( cd "$H" && git rm -qf --cached note.md && rm note.md )
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
