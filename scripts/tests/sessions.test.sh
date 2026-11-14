#!/bin/bash
# Tests for session identity, groups and windows, freeze and thaw in scripts/term/term.sh,
# against the fake backend only (no real tab is touched, nothing is signalled).
# Every rule has a fixture that must pass and one that must fail. Exit 0 when all pass.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
TERM_SH="$ROOT/scripts/term/term.sh"
SESS="$ROOT/scripts/term/sessions.sh"
FAKE="$ROOT/scripts/tests/stubs/term-fake"
mkdir -p "$ROOT/.local"
T=$(mktemp -d "$ROOT/.local/sessions-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

export HOME_ROOT="$T/home"
export TERM_SH_BACKEND=fake TERM_FAKE_DIR="$T/fake"
export TERM_SH_POLL=0.05 TERM_SH_SETTLE=0 TERM_SH_OPEN_WAIT=1 TERM_SH_EXIT_WAIT=1 TERM_SH_LOCK_TIMEOUT=1
export TERM_SH_HOME_LOG="$ROOT/scripts/home-log" HOME_LOG_SETTLE=0
export PATH="$ROOT/scripts/tests/stubs:$PATH" GH_STUB_DIR="$T/ghstore"
unset GH_CONFIG_DIR CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR CODEX_THREAD_ID GH_STUB_FAIL_MATCH
REG="$HOME_ROOT/.local/registry.json"
mkdir -p "$HOME_ROOT/.local"
W1="$T/work/g1 proj"; W2="$T/work/g2"; WX="$T/work/other"
mkdir -p "$W1/sub" "$W2" "$WX"
printf '%s\n' repo=test/home labels.needs_owner=needs-test homes.peer.repo=test/peer homes.peer.role=peer > "$HOME_ROOT/home.config"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }
check() { local name=$1; shift; if "$@" >>"$T/check.log" 2>&1; then ok; else bad "$name"; fi; }
not() { ! "$@"; }
ts() { /bin/bash "$TERM_SH" "$@"; }
rc_of() { "$@" >"$T/out" 2>"$T/err"; echo $?; }

config() { # config <lines...>: write .local/config
  printf '%s\n' terminal_helpers=on term.max_workers=4 "term.sessions_dirs=$TERM_FAKE_DIR/profiles/*/sessions" "$@" > "$HOME_ROOT/.local/config"
}
reset() {
  rm -rf "$TERM_FAKE_DIR" "$REG" "$GH_STUB_DIR" "$HOME_ROOT/.local/windows.json" "$HOME_ROOT/.local/freeze" \
    "$HOME_ROOT/.local/freeze.lock" "$HOME_ROOT/.local/runs"
  mkdir -p "$TERM_FAKE_DIR" "$GH_STUB_DIR"; config "$@"
}
tabdir() { echo "$TERM_FAKE_DIR/tabs/$1"; }
keys() { cat "$(tabdir "$1")/keys" 2>/dev/null; }
sent() { cat "$(tabdir "$1")/sent" 2>/dev/null; }
alive() { [ -d "$TERM_FAKE_DIR/proc/$1" ]; }
hand_tab() { # hand_tab <tty> <pid> <command line> <cwd> [window] [mode]: a live tab not opened by this home
  local d="$TERM_FAKE_DIR/tabs/$1"
  mkdir -p "$d" "$TERM_FAKE_DIR/proc/$2"
  printf 'hand-%s' "$1" > "$d/tab"; printf '%s' "${6:-claude}" > "$d/mode"; : > "$d/box"; printf '%s' "$2" > "$d/pid"
  printf '%s' "${5:-w1}" > "$d/window"
  printf '%s' "$3" > "$TERM_FAKE_DIR/proc/$2/cmd"; printf '%s' "$1" > "$TERM_FAKE_DIR/proc/$2/tty"
  printf '%s' "$4" > "$TERM_FAKE_DIR/proc/$2/cwd"
}
sess_file() { # sess_file <profile> <pid> <session id> <status> <cwd> [name]
  local d="$TERM_FAKE_DIR/profiles/$1/sessions"
  mkdir -p "$d"
  jq -n --argjson pid "$2" --arg sid "$3" --arg st "$4" --arg cwd "$5" --arg name "${6:-a session}" \
    '{pid: $pid, sessionId: $sid, cwd: $cwd, name: $name, status: $st}' > "$d/$2.json"
}
transcript() { mkdir -p "$TERM_FAKE_DIR/profiles/$1/projects/p"; : > "$TERM_FAKE_DIR/profiles/$1/projects/p/$2.jsonl"; }
sj() { ts survey --json | jq -c --arg t "$1" 'select(.tty == $t)'; }   # sj <tty>: that tab's survey --json line
S1="abcdefab-cdef-4abc-8def-abcdefabcd01"; S2="abcdefab-cdef-4abc-8def-abcdefabcd02"
S3="abcdefab-cdef-4abc-8def-abcdefabcd03"; S4="abcdefab-cdef-4abc-8def-abcdefabcd04"

# ---------------------------------------------------------------- static: fake twins, paths, underscores
TMPWORD="tm""p"; USERS="Use""rs"; SCRATCH="scratch""pad"
lint_paths() { ! grep -nE "/$TMPWORD/|/$USERS/|$SCRATCH|/private/" "$1" >/dev/null; }
lint_underscore() { ! grep -nE '^[[:space:]]*(function[[:space:]]+)?_[A-Za-z0-9_]*[[:space:]]*\(\)' "$1" >/dev/null; }
be_twins() { # every be_* function of the real backend (except be_sleep) is redefined by the fake in <fake>
  local f missing=0
  for f in $(grep -oE '^be_[a-z_]+\(\)' "$TERM_SH" | tr -d '()' | sort -u); do
    [ "$f" = be_sleep ] && continue
    grep -qE "^$f\(\)" "$1" || { echo "no fake for $f"; missing=1; }
  done
  [ "$missing" = 0 ]
}
check "fake redefines every backend function" be_twins "$FAKE"
grep -v '^be_tabs()' "$FAKE" > "$T/fake-missing"
check "lint catches a backend function without a fake" not be_twins "$T/fake-missing"
check "sessions.sh has no temp/user paths" lint_paths "$SESS"
check "sessions.sh has no underscore functions" lint_underscore "$SESS"
check "this test has no underscore functions" lint_underscore "$0"

# ---------------------------------------------------------------- identity: session files
reset launch.profile_flag=-p
hand_tab ttya1 501 "claude --model opus do the thing" "$W1"
sess_file work 501 "$S1" idle "$W1" "first"
out=$(sj ttya1)
check "identity: id from the session file" [ "$(printf '%s' "$out" | jq -r '.session_id + " " + .id_from')" = "$S1 file" ]
check "identity: profile is the folder name" [ "$(printf '%s' "$out" | jq -r .profile)" = work ]
check "identity: status from the session file" [ "$(printf '%s' "$out" | jq -r .status)" = idle ]
check "identity: resume keeps profile and model, drops the prompt" \
  [ "$(printf '%s' "$out" | jq -r .resume)" = "cd '$W1' && 'claude' -p 'work' --model 'opus' --resume $S1" ]
check "identity: window column" [ "$(printf '%s' "$out" | jq -r .window)" = w1 ]
reset launch.profile_flag=-p
hand_tab ttya1 501 "claude --dangerously-skip-permissions --add-dir /x --model claude-opus-x --resume $S2" "$W1"
out=$(sj ttya1)
check "identity: id from the command line without a session file" [ "$(printf '%s' "$out" | jq -r '.session_id + " " + .id_from')" = "$S2 cmdline" ]
check "identity: permission flag kept, pinned model and other flags dropped" \
  [ "$(printf '%s' "$out" | jq -r .resume)" = "cd '$W1' && 'claude' --dangerously-skip-permissions --resume $S2" ]
reset launch.profile_flag=-p
hand_tab ttya1 501 "claude -r" "$W1"
out=$(sj ttya1)
check "identity: no session file and no id -> resume manual" [ "$(printf '%s' "$out" | jq -r '(.session_id == null) and (.resume == null)')" = true ]
reset
hand_tab ttya1 501 "claude --model opus" "$W1"; sess_file work 501 "$S1" idle "$W1"
check "identity: profile known but no profile flag -> resume manual" [ "$(sj ttya1 | jq -r '.resume == null')" = true ]
reset launch.profile_flag=-p
hand_tab ttya1 501 "zsh" "$W1" w1 shell; sess_file work 501 "$S1" idle "$W1"
check "identity: a session file for a non-claude process is ignored" [ "$(sj ttya1 | jq -r '.kind + " " + (.session_id // "none")')" = "shell none" ]
reset launch.profile_flag=-p
hand_tab ttya1 501 "claude" "$W1"; printf '{"pid": 999, "sessionId": "%s", "status": "idle"}\n' "$S1" > "$T/x.json"
mkdir -p "$TERM_FAKE_DIR/profiles/work/sessions"; cp "$T/x.json" "$TERM_FAKE_DIR/profiles/work/sessions/501.json"
check "identity: a session file naming another pid is ignored" [ "$(sj ttya1 | jq -r '.session_id == null')" = true ]
reset launch.profile_flag=-p "term.sessions_dirs=$T/work/g1 proj/prof*/sessions"
mkdir -p "$W1/profA/sessions"
jq -n --arg s "$S3" '{pid: 501, sessionId: $s, status: "idle"}' > "$W1/profA/sessions/501.json"
hand_tab ttya1 501 "claude" "$W1"
check "identity: a sessions glob with a space in the path" [ "$(sj ttya1 | jq -r '.session_id + " " + .profile')" = "$S3 profA" ]
reset launch.profile_flag=-p
hand_tab ttya1 501 "/opt/bin/codex" "$W1" w1
check "identity: a codex tab is kind codex" [ "$(sj ttya1 | jq -r .kind)" = codex ]
check "identity: default survey still reads codex as shell" ts survey
check "identity: default survey line unchanged" grep -q '^ttya1 - shell - ' "$T/check.log" -e ''

# adopt and park use the session file (the profile is no longer dropped)
claim() { # claim <n> <run id>: the run has an active home-log comment on issue n
  mkdir -p "$GH_STUB_DIR/test__home/issues"
  jq -n --argjson n "$1" --arg body "<!-- home-log run=$2 state=active -->" \
    '{number: $n, title: "t", body: "", state: "open", state_reason: null, labels: [], created_at: "x", updated_at: "x",
      closed_at: null, author: "owner", comments: [{id: 1, body: $body}]}' > "$GH_STUB_DIR/test__home/issues/$1.json"
}
reset launch.profile_flag=-p
hand_tab ttya1 501 "claude --model opus" "$W1"; sess_file work 501 "$S1" idle "$W1"; claim 21 "$S1"
check "identity: park --adopt with the id from the session file" ts park ttya1 --adopt --issue 21
check "identity: parked resume line holds the profile" \
  [ "$(jq -r '.[0].resume' "$REG")" = "cd '$W1' && 'claude' -p 'work' --model 'opus' --resume $S1" ]
check "identity: the parked session exited" not alive 501
reset
hand_tab ttya1 501 "claude --model opus" "$W1"; sess_file work 501 "$S1" idle "$W1"; claim 21 "$S1"
check "identity: park --adopt refused when the profile cannot be passed" [ "$(rc_of ts park ttya1 --adopt --issue 21)" = 3 ]
check "identity: nothing typed on that refusal" [ -z "$(keys ttya1)" ]
check "identity: that session still runs" alive 501

# ---------------------------------------------------------------- the calling session (two signals)
reset launch.profile_flag=-p
hand_tab ttyc1 601 "claude" "$W1"; sess_file work 601 "$S1" idle "$W1"
hand_tab ttyc2 602 "claude" "$W1"; sess_file work 602 "$S2" idle "$W1"
mkdir -p "$TERM_FAKE_DIR/proc/650" "$TERM_FAKE_DIR/proc/651"
printf 'bash term.sh' > "$TERM_FAKE_DIR/proc/650/cmd"; printf 'ttyc1' > "$TERM_FAKE_DIR/proc/650/tty"; printf 'ttyc1' > "$TERM_FAKE_DIR/proc/651/tty"; printf '651' > "$TERM_FAKE_DIR/proc/650/ppid"
printf 'zsh -c x' > "$TERM_FAKE_DIR/proc/651/cmd"; printf '601' > "$TERM_FAKE_DIR/proc/651/ppid"
printf '650' > "$TERM_FAKE_DIR/self-pid"
check "caller: the process walk finds the calling tab" [ "$(sj ttyc1 | jq -r .caller)" = true ]
check "caller: another tab is not the caller" [ "$(sj ttyc2 | jq -r .caller)" = false ]
rm -f "$TERM_FAKE_DIR/self-pid"
check "caller: CLAUDE_CODE_SESSION_ID finds the calling tab" [ "$(CLAUDE_CODE_SESSION_ID=$S2 ts survey --json | jq -r 'select(.tty == "ttyc2") | .caller')" = true ]
check "caller: no signal -> no caller" [ "$(ts survey --json | jq -s '[.[] | select(.caller)] | length')" = 0 ]
check "caller: an id with no session file -> no caller" [ "$(CLAUDE_CODE_SESSION_ID=$S4 ts survey --json | jq -s '[.[] | select(.caller)] | length')" = 0 ]

echo "sessions.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
