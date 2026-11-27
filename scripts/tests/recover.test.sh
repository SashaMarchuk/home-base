#!/bin/bash
# Tests for reconcile, adopt, reopen and regroup in scripts/term/term.sh (scripts/term/recover.sh),
# against the fake backend only (no real tab is touched, nothing is signalled).
# Every rule has a fixture that must pass and one that must fail. Exit 0 when all pass.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
TERM_SH="$ROOT/scripts/term/term.sh"
mkdir -p "$ROOT/.local"
T=$(mktemp -d "$ROOT/.local/recover-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

export HOME_ROOT="$T/home"
export TERM_SH_BACKEND=fake TERM_FAKE_DIR="$T/fake"
export TERM_SH_POLL=0.05 TERM_SH_SETTLE=0 TERM_SH_OPEN_WAIT=1 TERM_SH_EXIT_WAIT=1 TERM_SH_LOCK_TIMEOUT=1
export TERM_SH_HOME_LOG="$ROOT/scripts/home-log" HOME_LOG_SETTLE=0
export PATH="$ROOT/scripts/tests/stubs:$PATH" GH_STUB_DIR="$T/ghstore"
unset GH_CONFIG_DIR CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR CODEX_THREAD_ID GH_STUB_FAIL_MATCH
REG="$HOME_ROOT/.local/registry.json"
mkdir -p "$HOME_ROOT/.local"
W1="$T/work/g1"; W2="$T/work/g2"
mkdir -p "$W1" "$W2"
printf '%s\n' repo=test/home labels.needs_owner=needs-test > "$HOME_ROOT/home.config"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }
check() { local name=$1; shift; if "$@" >>"$T/check.log" 2>&1; then ok; else bad "$name"; fi; }
not() { ! "$@"; }
ts() { /bin/bash "$TERM_SH" "$@"; }
rc_of() { "$@" >"$T/out" 2>"$T/err"; echo $?; }
out_has() { grep -qxF -- "$1" "$T/out"; }

config() {
  printf '%s\n' terminal_helpers=on term.max_workers=4 "term.sessions_dirs=$TERM_FAKE_DIR/profiles/*/sessions" \
    launch.profile_flag=-p term.groups=g1,g2 "term.group.g1.cwd=$W1" "term.group.g2.cwd=$W2" "$@" > "$HOME_ROOT/.local/config"
}
reset() { rm -rf "$TERM_FAKE_DIR" "$REG" "$GH_STUB_DIR" "$HOME_ROOT/.local/windows.json"; mkdir -p "$TERM_FAKE_DIR" "$GH_STUB_DIR"; config "$@"; }
tabdir() { echo "$TERM_FAKE_DIR/tabs/$1"; }
keys() { cat "$(tabdir "$1")/keys" 2>/dev/null; }
nokeys() { local t; for t in "$@"; do [ -z "$(keys "$t")" ] || return 1; done; }
hand_tab() { # hand_tab <tty> <pid> <command line> <cwd> [window] [mode]: a live tab not opened by this home
  local d="$TERM_FAKE_DIR/tabs/$1"
  mkdir -p "$d" "$TERM_FAKE_DIR/proc/$2"
  printf 'hand-%s' "$1" > "$d/tab"; printf '%s' "${6:-claude}" > "$d/mode"; : > "$d/box"; printf '%s' "$2" > "$d/pid"
  printf '%s' "${5:-w1}" > "$d/window"
  printf '%s' "$3" > "$TERM_FAKE_DIR/proc/$2/cmd"; printf '%s' "$1" > "$TERM_FAKE_DIR/proc/$2/tty"
  printf '%s' "$4" > "$TERM_FAKE_DIR/proc/$2/cwd"
}
sess_file() { # sess_file <profile> <pid> <session id> <cwd>
  local d="$TERM_FAKE_DIR/profiles/$1/sessions"
  mkdir -p "$d"
  jq -n --argjson pid "$2" --arg sid "$3" --arg cwd "$4" '{pid: $pid, sessionId: $sid, cwd: $cwd, name: "n", status: "idle"}' > "$d/$2.json"
}
live() { hand_tab "$1" "$2" "claude --model opus" "$3" "${5:-w1}"; sess_file work "$2" "$4" "$3"; }   # live <tty> <pid> <cwd> <sid> [window]
entry() { # entry <session id> <tty> <tab> <pid> <cwd> [extra jq object]: an open registry entry of a session this home opened
  local cur='[]' x=${6:-}; [ -f "$REG" ] && cur=$(cat "$REG"); [ -n "$x" ] || x='{}'
  printf '%s' "$cur" | jq --arg s "$1" --arg t "$2" --arg tab "$3" --argjson p "$4" --arg c "$5" --argjson x "$x" \
    '. + [{session_id: $s, tty: $t, pid: $p, cwd: $c, issue: null, resume: ("cd '"'"'" + $c + "'"'"' && '"'"'claude'"'"' -p '"'"'work'"'"' --model '"'"'opus'"'"' --resume " + $s),
      opened: "2026-01-01T00:00:00Z", closed: null, role: "worker", tab: $tab, match: $s} + $x]' > "$REG.x" && mv "$REG.x" "$REG"
}
field() { jq -r --arg s "$1" ".[] | select(.session_id == \$s) | $2" "$REG"; }   # field <session id> <jq path>
S1="abcdefab-cdef-4abc-8def-abcdefabcd01"; S2="abcdefab-cdef-4abc-8def-abcdefabcd02"
S3="abcdefab-cdef-4abc-8def-abcdefabcd03"; S4="abcdefab-cdef-4abc-8def-abcdefabcd04"
S5="abcdefab-cdef-4abc-8def-abcdefabcd05"; S6="abcdefab-cdef-4abc-8def-abcdefabcd06"

lint_underscore() { ! grep -nE '^[[:space:]]*(function[[:space:]]+)?_[A-Za-z0-9_]*[[:space:]]*\(\)' "$1" >/dev/null; }
TMPWORD="tm""p"; USERS="Use""rs"; PRIV="priv""ate"
lint_paths() { ! grep -nE "/$TMPWORD/|/$USERS/|/$PRIV/" "$1" >/dev/null; }
check "recover.sh has no underscore functions" lint_underscore "$ROOT/scripts/term/recover.sh"
check "recover.sh has no temp/user paths" lint_paths "$ROOT/scripts/term/recover.sh"

# ---------------------------------------------------------------- reconcile: two signals, never silence
# The state after a reboot: S1 and S2 were open on ttyx1/ttyx2 (tabs and processes gone); ttyx1 is reused by a new tab.
issue_with() { # issue_with <n> <state> [<run> <home-log state>]...: the issue with one home-log comment per run
  local n=$1 st=$2 c='[]' i=3; shift 2
  while [ $# -ge 2 ]; do
    c=$(printf '%s' "$c" | jq -c --argjson id "$i" --arg b "<!-- home-log run=$1 state=$2 -->" '. + [{id: $id, body: $b}]'); i=$((i + 1)); shift 2
  done
  mkdir -p "$GH_STUB_DIR/test__home/issues"
  jq -n --argjson n "$n" --arg st "$st" --argjson c "$c" '{number: $n, title: "t", body: "", state: $st, state_reason: null,
    labels: [], created_at: "x", updated_at: "x", closed_at: null, author: "owner", comments: $c}' > "$GH_STUB_DIR/test__home/issues/$n.json"
}
reboot() {
  reset "$@"
  entry "$S1" ttyx1 tab-old-1 901 "$W1"; entry "$S2" ttyx2 tab-old-2 902 "$W2" '{"issue": 21}'
  issue_with 21 open "$S2" active
  live ttyx1 951 "$W1" "$S5" w3   # the orchestrator's own tab after the reboot, on a reused tty
}
reboot
cp "$REG" "$T/reg.before"
ts survey >/dev/null 2>&1; ts survey --json >/dev/null 2>&1; ts finished >/dev/null 2>&1
check "reconcile: survey and finished write nothing" cmp -s "$REG" "$T/reg.before"
check "reconcile --dry-run exits 0" [ "$(rc_of ts reconcile --dry-run)" = 0 ]
check "reconcile --dry-run lists both" [ "$(grep -c '^PLAN lost ' "$T/out")" = 2 ]
check "reconcile --dry-run writes nothing" cmp -s "$REG" "$T/reg.before"
check "reconcile exits 0" [ "$(rc_of ts reconcile)" = 0 ]
check "reconcile prints one line per change" [ "$(sort "$T/out" | tr '\n' ' ')" = "LOST $S1 ttyx1 LOST $S2 ttyx2 " ]
check "reconcile marks lost, not closed" [ "$(field "$S1" '(.lost != null) and (.closed == null)')" = true ]
check "reconcile keeps the old tty as lost_tty and clears tty, tab and pid" \
  [ "$(field "$S1" '"\(.lost_tty) \(.lost_tab) \(.lost_pid) \(.tty) \(.tab) \(.pid)"')" = "ttyx1 tab-old-1 901 null null null" ]
check "reconcile keeps the issue" [ "$(field "$S2" .issue)" = 21 ]
cp "$REG" "$T/reg.after"
check "reconcile again exits 0" [ "$(rc_of ts reconcile)" = 0 ]
check "reconcile again prints nothing" [ ! -s "$T/out" ]
check "reconcile again changes nothing" cmp -s "$REG" "$T/reg.after"
issue_final() { # issue_final <n> <run id>: the issue holds a final home-log comment of that run
  mkdir -p "$GH_STUB_DIR/test__home/issues"
  jq -n --argjson n "$1" --arg b "<!-- home-log run=$2 state=final -->" \
    '{number: $n, title: "t", body: "", state: "open", state_reason: null, labels: [], created_at: "x", updated_at: "x",
      closed_at: null, author: "owner", comments: [{id: 3, body: $b}]}' > "$GH_STUB_DIR/test__home/issues/$1.json"
}
issue_final 21 "$S1"; issue_final 22 "$S5"
check "a lost session is never typed into: resume names reopen" [ "$(rc_of ts resume "$S1")" = 3 ]
check "the refusal names reopen" grep -qF "term.sh reopen $S1" "$T/err"
check "the reused tty is not the lost session's: close refuses" [ "$(rc_of ts close ttyx1 --issue 21)" = 3 ]
check "close refuses because the tab is not registered" grep -q "none recorded on ttyx1" "$T/err"
check "nothing typed into the reused tty" nokeys ttyx1

reset; entry "$S1" ttyx1 tab-old-1 901 "$W1"; live ttyx9 959 "$W1" "$S5"
mkdir -p "$TERM_FAKE_DIR/proc/901"; printf 'claude --session-id %s' "$S1" > "$TERM_FAKE_DIR/proc/901/cmd"; printf ttyx1 > "$TERM_FAKE_DIR/proc/901/tty"
ts reconcile >/dev/null 2>&1
check "reconcile: tab gone, process alive -> not lost" [ "$(field "$S1" '.lost == null and .tty == "ttyx1"')" = true ]
reset; live ttyx1 951 "$W1" "$S5"; entry "$S1" ttyx1 hand-ttyx1 901 "$W1"
ts reconcile >/dev/null 2>&1
check "reconcile: tab live (same tab id) running another session, process gone -> lost" [ "$(field "$S1" '.lost != null')" = true ]
# a window restored after a restart: the same tab id on the same tty, a fresh shell only
reset; live ttyx9 959 "$W1" "$S5"; hand_tab ttyx1 931 "-zsh" "$W1" w1 shell; entry "$S1" ttyx1 hand-ttyx1 901 "$W1"
ts reconcile >/dev/null 2>&1
check "reconcile: restored tab (same id and tty, a shell only) -> lost" [ "$(field "$S1" '.lost != null')" = true ]
reset; live ttyx9 959 "$W1" "$S5"; hand_tab ttyx7 931 "-zsh" "$W1" w1 shell; printf 'hand-ttyx1' > "$(tabdir ttyx7)/tab"
entry "$S1" ttyx1 hand-ttyx1 901 "$W1"
ts reconcile >/dev/null 2>&1
check "reconcile: the tab id on another tty, process gone -> lost" [ "$(field "$S1" '.lost != null')" = true ]
# resumed by hand in its own tab after a crash: a new PID on that tty carries the session id
reset; live ttyx9 959 "$W1" "$S5"; hand_tab ttyx1 932 "claude --resume $S1" "$W1"; entry "$S1" ttyx1 hand-ttyx1 901 "$W1"
ts reconcile >/dev/null 2>&1
check "reconcile: dead PID, its session id runs again on its tty -> not lost" [ "$(field "$S1" '.lost == null and .tty == "ttyx1"')" = true ]
reset; live ttyx9 959 "$W1" "$S5"; hand_tab ttyx1 932 "vim $S1" "$W1"; entry "$S1" ttyx1 hand-ttyx1 901 "$W1"
ts reconcile >/dev/null 2>&1
check "reconcile: the session id on a command that is not claude -> lost" [ "$(field "$S1" '.lost != null')" = true ]
reset; live ttyx9 959 "$W1" "$S5"; entry "$S1" ttyx1 tab-old-1 901 "$W1"
mkdir -p "$TERM_FAKE_DIR/proc/901"; printf 'vim notes' > "$TERM_FAKE_DIR/proc/901/cmd"; printf ttyx1 > "$TERM_FAKE_DIR/proc/901/tty"
ts reconcile >/dev/null 2>&1
check "reconcile: a reused PID running something else counts as gone" [ "$(field "$S1" '.lost != null')" = true ]
reset; live ttyx9 959 "$W1" "$S5"; entry "$S1" ttyx1 tab-old-1 901 "$W1" '{"pid": null}'
ts reconcile >/dev/null 2>&1
check "reconcile: no pid recorded (one signal) -> not lost" [ "$(field "$S1" '.lost == null')" = true ]
reboot; cp "$REG" "$T/reg.before"; : > "$TERM_FAKE_DIR/tabs-fail"
check "reconcile: tabs cannot be read -> exit 3" [ "$(rc_of ts reconcile)" = 3 ]
check "reconcile: unreadable tabs mark nothing" cmp -s "$REG" "$T/reg.before"
reboot; rm -rf "$TERM_FAKE_DIR/tabs"; cp "$REG" "$T/reg.before"
check "reconcile: no live tab at all -> exit 3" [ "$(rc_of ts reconcile)" = 3 ]
check "reconcile: no live tab marks nothing" cmp -s "$REG" "$T/reg.before"

# ---------------------------------------------------------------- adopt
reset
live ttya1 701 "$W1" "$S1" w5
check "adopt: a hand tab -> exit 0" [ "$(rc_of ts adopt ttya1)" = 0 ]
check "adopt: prints the tab, id and group" out_has "ADOPTED ttya1 $S1 g1"
check "adopt: adopted owner tab with its resume line" [ "$(field "$S1" '"\(.adopted) \(.role) \(.resume)"')" = "true owner cd '$W1' && 'claude' -p 'work' --model 'opus' --resume $S1" ]
check "adopt: profile, model, cwd, window, group" [ "$(field "$S1" '"\(.profile) \(.model) \(.cwd) \(.window) \(.group) \(.group_from) \(.issue)"')" = "work opus $W1 w5 g1 cwd null" ]
check "adopt: nothing typed" nokeys ttya1
check "adopt: the tab is registered now" [ "$(ts survey)" = "ttya1 701 claude $S1 $W1" ]
check "adopt: finished keeps it as the owner's tab" [ "$(ts finished)" = "ttya1 $S1 - keep:owner-tab" ]
issue_final 5 "$S1"
check "adopt: close without --adopt still refuses" [ "$(rc_of ts close ttya1 --issue 5)" = 3 ]
check "adopt: the refusal is for the owner's tab, not the issue" grep -q "is the owner's own (recorded with --adopt)" "$T/err"
check "adopt: refused close typed nothing" nokeys ttya1
check "adopt: a registered tab -> exit 3" [ "$(rc_of ts adopt ttya1)" = 3 ]
check "adopt: it says registered already" grep -q "^SKIP ttya1: registered already" "$T/out"
check "adopt: still one entry" [ "$(jq length "$REG")" = 1 ]
reset; live ttya1 701 "$W1" "$S1"
check "adopt --issue --repo --group -> exit 0" [ "$(rc_of ts adopt ttya1 --issue 12 --repo o/r --group g2)" = 0 ]
check "adopt: issue, repo and the named group are recorded" [ "$(field "$S1" '"\(.issue) \(.repo) \(.group) \(.group_from)"')" = "12 o/r g2 explicit" ]
reset; live ttya1 701 "$W1" "$S1"
check "adopt: unknown group -> exit 2" [ "$(rc_of ts adopt ttya1 --group nope)" = 2 ]
check "adopt: --issue with no value -> exit 2" [ "$(rc_of ts adopt ttya1 --issue)" = 2 ]
check "adopt: --repo with no value -> exit 2" [ "$(rc_of ts adopt ttya1 --issue 3 --repo)" = 2 ]
check "adopt: --issue with --all -> exit 2" [ "$(rc_of ts adopt --all --issue 3)" = 2 ]
check "adopt: --repo without --issue -> exit 2" [ "$(rc_of ts adopt ttya1 --repo o/r)" = 2 ]
check "adopt: a title is no target -> exit 2" [ "$(rc_of ts adopt "my tab")" = 2 ]
check "adopt: usage errors record nothing" [ ! -f "$REG" ]
reset; hand_tab ttya1 701 "claude -r" "$W1"
check "adopt: no session id -> exit 3" [ "$(rc_of ts adopt ttya1)" = 3 ]
check "adopt: no session id records nothing" [ "$(jq length "$REG" 2>/dev/null || echo 0)" = 0 ]
reset; live ttya1 701 "$W1" "$S1"
mkdir -p "$TERM_FAKE_DIR/proc/709"; printf 'claude' > "$TERM_FAKE_DIR/proc/709/cmd"; printf ttya1 > "$TERM_FAKE_DIR/proc/709/tty"
check "adopt: two sessions on the tty -> exit 3" [ "$(rc_of ts adopt ttya1)" = 3 ]
check "adopt: no tab on the tty -> exit 4" [ "$(rc_of ts adopt ttyzz)" = 4 ]
check "adopt: a skipped tab before a missing one -> exit 3" [ "$(rc_of ts adopt ttya1 ttyzz)" = 3 ]
reset; live ttya1 701 "$W1" "$S1"; hand_tab ttya2 702 "claude --resume $S2" "$W2" w2; live ttya3 703 "$W1" "$S3"
hand_tab ttya4 704 "-zsh" "$W1" w1 shell; live ttya5 705 "$W2" "$S5"; ts adopt ttya5 >/dev/null 2>&1
printf 703 > "$TERM_FAKE_DIR/self-pid"   # this session runs in ttya3
check "adopt --all -> exit 0" [ "$(rc_of ts adopt --all)" = 0 ]
check "adopt --all adopts the hand tabs" [ "$(grep -c '^ADOPTED ' "$T/out")" = 2 ]
check "adopt --all takes the id from the command line too" out_has "ADOPTED ttya2 $S2 g2"
check "adopt --all leaves this session's own tab" [ -z "$(field "$S3" .tty)" ]
check "adopt --all says so" grep -q "^SKIP ttya3: this session's own tab" "$T/out"
check "adopt --all leaves a registered tab alone" [ "$(jq --arg s "$S5" '[.[] | select(.session_id == $s)] | length' "$REG")" = 1 ]
check "adopt --all typed nothing" nokeys ttya1 ttya2 ttya3 ttya4 ttya5
check "adopt: the caller's tab named by its tty is adopted" [ "$(rc_of ts adopt ttya3)" = 0 ]
rm -f "$TERM_FAKE_DIR/self-pid"
# the same tab, a new process and session: the old entry is stale and gives the new one neither its group nor its role
reset launch.profile.worker=wprof
hand_tab ttya1 722 "claude --model opus --resume $S2" "$W1" w1
entry "$S1" ttya1 hand-ttya1 721 "$W1" '{"group": "g2", "role": "worker"}'
check "survey --json: a stale tab with no session file names the live id" [ "$(ts survey --json | jq -r 'select(.tty == "ttya1") | "\(.session_id) \(.group)"')" = "$S2 g1" ]
check "adopt --all on a stale tab -> exit 0" [ "$(rc_of ts adopt --all)" = 0 ]
check "adopt --all adopts the new session of a stale tab" out_has "ADOPTED ttya1 $S2 g1"
check "the stale entry's role gives the resume line no profile" [ "$(field "$S2" .resume)" = "cd '$W1' && 'claude' --model 'opus' --resume $S2" ]
reboot
check "adopt after a reboot: the reused tty is adopted" [ "$(rc_of ts adopt ttyx1)" = 0 ]
check "adopt after a reboot: the old entries are marked lost first" grep -q "^LOST $S1 ttyx1" "$T/out"
check "adopt after a reboot: the new session is recorded" [ "$(field "$S5" '"\(.tty) \(.adopted)"')" = "ttyx1 true" ]
reset; entry "$S1" ttyx1 tab-old-1 901 "$W1" '{"issue": 21, "lost": "2026-01-01T00:00:00Z", "tty": null, "tab": null, "pid": null}'
live ttyb1 711 "$W1" "$S1" w4
check "adopt: a lost session running again is taken over" [ "$(rc_of ts adopt ttyb1)" = 0 ]
check "adopt: one entry for that session" [ "$(jq --arg s "$S1" '[.[] | select(.session_id == $s)] | length' "$REG")" = 1 ]
check "adopt: it follows the session into the tab and keeps its issue" [ "$(field "$S1" '"\(.tty) \(.pid) \(.lost) \(.issue) \(.adopted)"')" = "ttyb1 711 null 21 true" ]
# the profile: the process's CLAUDE_CONFIG_DIR wins over the folder of its session file (a shared sessions folder)
reset; live ttya1 701 "$W1" "$S1"; printf 'TERM=xterm CLAUDE_CONFIG_DIR=/x/profiles/home2 LANG=C' > "$TERM_FAKE_DIR/proc/701/env"
check "adopt: a profile from the process environment -> exit 0" [ "$(rc_of ts adopt ttya1)" = 0 ]
check "adopt: the environment's profile is recorded and in the resume line" \
  [ "$(field "$S1" '"\(.profile) \(.resume)"')" = "home2 cd '$W1' && 'claude' -p 'home2' --model 'opus' --resume $S1" ]
# no profile flag: the profile cannot be passed, so the tab has no resume line, and adopt says so
reset launch.profile_flag=; live ttya1 701 "$W1" "$S1"
check "adopt with no profile flag -> exit 0" [ "$(rc_of ts adopt ttya1)" = 0 ]
check "adopt with no profile flag records no resume line" [ "$(field "$S1" '"\(.resume) \(.profile) \(.model)"')" = "null work opus" ]
check "adopt with no profile flag says reopen cannot bring it back" grep -q "^NOTE ttya1: it runs under profile 'work' and launch.profile_flag is empty" "$T/out"

# a crashed worker resumed by hand in its own tab: its open entry follows the new PID, nothing else changes
reset; entry "$S1" ttyb1 hand-ttyb1 901 "$W1" '{"issue": 21}'; hand_tab ttyb1 712 "claude --resume $S1" "$W1"; sess_file work 712 "$S1" "$W1"
check "adopt: a session resumed by hand in its own tab -> exit 0" [ "$(rc_of ts adopt ttyb1)" = 0 ]
check "adopt: says the entry was updated" grep -q "^UPDATED ttyb1 $S1" "$T/out"
check "adopt: the one entry takes the new PID and keeps role, issue and adopted" \
  [ "$(jq -c --arg s "$S1" '[.[] | select(.session_id == $s) | [.pid, .tty, .role, .issue, (.adopted // false), .match == $s, .lost]]' "$REG")" = '[[712,"ttyb1","worker",21,false,true,null]]' ]
check "adopt: the updated tab is registered now" [ "$(ts survey)" = "ttyb1 712 claude $S1 $W1" ]
check "adopt: the update typed nothing" nokeys ttyb1
reset; live ttyx9 959 "$W1" "$S5"; entry "$S1" ttyb1 hand-ttyb1 901 "$W1"; hand_tab ttyb1 712 "claude --resume $S1" "$W1"
mkdir -p "$TERM_FAKE_DIR/proc/901"; printf 'claude --session-id %s' "$S1" > "$TERM_FAKE_DIR/proc/901/cmd"; printf ttyb1 > "$TERM_FAKE_DIR/proc/901/tty"
check "adopt: the recorded PID still runs -> exit 3" [ "$(rc_of ts adopt ttyb1)" = 3 ]
check "adopt: the live entry keeps its PID" [ "$(field "$S1" .pid)" = 901 ]
# two closed entries of one session: only the last one is taken over
reset; entry "$S1" ttyx1 tab-old-1 901 "$W1" '{"issue": 7, "closed": "2026-01-01T00:00:00Z"}'
entry "$S1" ttyx2 tab-old-2 902 "$W1" '{"issue": 8, "closed": "2026-01-02T00:00:00Z"}'
live ttyb1 711 "$W1" "$S1" w4
check "adopt: two closed entries of the session -> exit 0" [ "$(rc_of ts adopt ttyb1)" = 0 ]
check "adopt: only the last entry follows the session" \
  [ "$(jq -c '[.[] | [.issue, .tty, .closed != null]]' "$REG")" = '[[7,"ttyx1",true],[8,"ttyb1",false]]' ]

# ---------------------------------------------------------------- reopen
issue_q() { # issue_q <n> <run id> <extra line>: the issue holds that run's home-log comment
  mkdir -p "$GH_STUB_DIR/test__home/issues"
  jq -n --argjson n "$1" --arg b "$(printf '<!-- home-log run=%s state=parked -->\n**home-log** . parked\n- run: %s\n%s\n' "$2" "$2" "$3")" \
    '{number: $n, title: "t", body: "", state: "open", state_reason: null, labels: [], created_at: "x", updated_at: "x",
      closed_at: null, author: "owner", comments: [{id: 3, body: $b}]}' > "$GH_STUB_DIR/test__home/issues/$1.json"
}
launched() { grep -F -- "--resume $1" "$TERM_FAKE_DIR/launches" 2>/dev/null; }
launched_has() { launched "$1" | grep -qF -- "$2"; }   # launched_has <session id> <text>: its launch line holds the text
placed_win() { awk -v t="$1" '$1 == t { print $2 }' "$TERM_FAKE_DIR/placed"; }
reboot; entry "$S3" ttyx3 tab-old-3 903 "$W1"
issue_q 21 "$S2" "- Open question for the owner: Which region?"
cp "$REG" "$T/reg.before"
check "reopen --dry-run -> exit 0" [ "$(rc_of ts reopen --lost --dry-run)" = 0 ]
check "reopen --dry-run plans the would-be-lost sessions" [ "$(grep -c '^PLAN ' "$T/out")" = 3 ]
check "reopen --dry-run writes and opens nothing" [ ! -f "$TERM_FAKE_DIR/launches" ]
check "reopen --dry-run leaves the registry" cmp -s "$REG" "$T/reg.before"
check "reopen --lost -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen marks them lost first" grep -q "^LOST $S1 ttyx1" "$T/out"
check "reopen reopens all three" [ "$(grep -c '^REOPENED ' "$T/out")" = 3 ]
check "reopen: g1 before g2" [ "$(grep '^REOPENED ' "$T/out" | awk '{ print $2 }' | tr '\n' ' ')" = "$S1 $S3 $S2 " ]
check "reopen: the recorded resume line with profile and model" launched_has "$S1" "cd '$W1' && 'claude' -p 'work' --model 'opus' --resume $S1 "
check "reopen: the restart note when no question is open" launched_has "$S1" "You were reopened after a restart; your conversation is intact. Continue where you stopped"
check "reopen: the open question is re-asked" launched_has "$S2" "Re-ask your open question with the ask tool, then continue."
t1=$(field "$S1" .tty); t2=$(field "$S2" .tty); t3=$(field "$S3" .tty)
check "reopen: one window per group (g1 together)" [ "$(placed_win "$t1")" = "$(placed_win "$t3")" ]
check "reopen: g2 in another window" [ "$(placed_win "$t2")" != "$(placed_win "$t1")" ]
check "reopen: the registry has the new tty and pid, not lost" [ "$(field "$S1" '(.tty != null) and (.pid != null) and (.lost == null) and (.lost_tty == null) and (.closed == null)')" = true ]
check "reopen: the issue is kept" [ "$(field "$S2" .issue)" = 21 ]
check "reopen: nothing typed into any tab" nokeys ttyx1 "$t1" "$t2" "$t3"
cp "$TERM_FAKE_DIR/launches" "$T/launches.before"
check "reopen again -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen again opens nothing" cmp -s "$TERM_FAKE_DIR/launches" "$T/launches.before"
# an orchestrator with term.role.orchestrator.window: its own window and its name; its group stays
reboot term.role.orchestrator.window=Orchestrators; entry "$S3" ttyx3 tab-old-3 903 "$W1" '{"role": "orchestrator"}'
check "reopen: with a role window -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
t1=$(field "$S1" .tty); t3=$(field "$S3" .tty)
check "reopen: the orchestrator is not placed with its group's worker" [ "$(placed_win "$t3")" != "$(placed_win "$t1")" ]
check "reopen: the orchestrator keeps its group" [ "$(field "$S3" .group)" = g1 ]
check "reopen: the orchestrator starts under its name" launched_has "$S3" "--resume $S3 --name 'Orchestrator "$'\xc2\xb7'" $(basename "$W1")'"
check "reopen: the role window is cached" [ "$(jq -r '.[] | select(.group == "Orchestrators") | .window' "$HOME_ROOT/.local/windows.json")" = "$(placed_win "$t3")" ]

reboot; entry "$S3" ttyx3 tab-old-3 903 "$W1"
mkdir -p "$TERM_FAKE_DIR/proc/990"; printf 'claude --resume %s' "$S3" > "$TERM_FAKE_DIR/proc/990/cmd"; printf ttyq9 > "$TERM_FAKE_DIR/proc/990/tty"
check "reopen: a session already running -> exit 0" [ "$(rc_of ts reopen "$S3")" = 0 ]
check "reopen: it is skipped" grep -q "^SKIP $S3: it runs already" "$T/out"
check "reopen: it is not launched" [ -z "$(launched "$S3")" ]
check "reopen <id> reopens only that id" [ -z "$(launched "$S1")" ]
check "reopen <id>: the others stay lost" [ "$(field "$S1" '.lost != null')" = true ]
check "reopen <id> --message" [ "$(rc_of ts reopen "$S1" --message "Check the deploy first.")" = 0 ]
check "reopen: --message replaces the note" launched_has "$S1" "'Check the deploy first.'"
check "reopen: a multi-line message -> exit 2" [ "$(rc_of ts reopen "$S2" --message "$(printf 'a\nb')")" = 2 ]
check "reopen: --lost with ids -> exit 2" [ "$(rc_of ts reopen --lost "$S2")" = 2 ]
check "reopen: a session id that is not lost is named" [ "$(rc_of ts reopen "$S5")" = 0 ]
check "reopen: says it is not lost" grep -q "^SKIP $S5: no lost entry" "$T/out"
reboot; jq --arg s "$S1" 'map(if .session_id == $s then .resume = null else . end)' "$REG" > "$REG.x" && mv "$REG.x" "$REG"
check "reopen: no resume line -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen: no resume line is skipped, never rebuilt" grep -q "^SKIP $S1: no resume line" "$T/out"
check "reopen: no resume line not launched" [ -z "$(launched "$S1")" ]
reboot; : > "$TERM_FAKE_DIR/open-fail"
check "reopen: a tab that does not open -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen: it says FAILED" grep -q "^FAILED $S1: the tab did not open" "$T/out"
check "reopen: it stays lost for the next run" [ "$(field "$S1" '(.lost != null) and (.closed == null)')" = true ]
rm -f "$TERM_FAKE_DIR/open-fail"
check "reopen after the failure reopens it" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen after the failure: REOPENED" grep -q "^REOPENED $S1 " "$T/out"
reboot; printf 5 > "$TERM_FAKE_DIR/mem_free"
check "reopen: low memory -> exit 3" [ "$(rc_of ts reopen --lost)" = 3 ]
check "reopen: low memory opens nothing" [ ! -f "$TERM_FAKE_DIR/launches" ]
check "reopen: low memory names reopen --lost" grep -q "reopen --lost" "$T/out"
reboot term.max_workers=1
entry "$S4" ttyx4 tab-old-4 904 "$W2"
hand_tab ttyw1 961 "claude --session-id $S3" "$W2"; entry "$S3" ttyw1 hand-ttyw1 961 "$W2"   # one live worker already
check "reopen: at the worker cap -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen: workers are queued" [ "$(grep -c '^QUEUED ' "$T/out")" = 3 ]
check "reopen: a queued session stays lost" [ "$(field "$S4" '.lost != null')" = true ]

# reopen rebuilds a missing or partial line from the recorded profile and model only
reset; live ttyx9 959 "$W1" "$S5"
entry "$S1" ttyx1 tab-old-1 901 "$W1" '{"resume": null, "profile": "work", "model": "opus", "adopted": true, "role": "owner"}'
entry "$S2" ttyx2 tab-old-2 902 "$W2" "{\"resume\": \"cd '$W2' && 'claude' --dangerously-skip-permissions --resume $S2\", \"profile\": \"home2\", \"model\": null}"
entry "$S3" ttyx3 tab-old-3 903 "$W1" '{"resume": null, "profile": null, "model": null}'
check "reopen with recorded profiles -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen: no line, recorded profile and model -> rebuilt" launched_has "$S1" "cd '$W1' && 'claude' -p 'work' --model 'opus' --resume $S1 "
check "reopen: a line without the recorded profile -> rebuilt with it, keeping its flags" \
  launched_has "$S2" "cd '$W2' && 'claude' -p 'home2' --dangerously-skip-permissions --resume $S2 "
check "reopen: nothing recorded -> still skipped" grep -q "^SKIP $S3: no resume line recorded" "$T/out"
reset launch.profile_flag=; live ttyx9 959 "$W1" "$S5"
entry "$S1" ttyx1 tab-old-1 901 "$W1" '{"resume": null, "profile": "work", "model": null}'
check "reopen: a recorded profile with no flag -> skipped" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen: the profile is never dropped silently" grep -q "^SKIP $S1: no resume line recorded" "$T/out"
# a lost session whose issue is done or taken over is never reopened; forget drops it
reboot; entry "$S3" ttyx3 tab-old-3 903 "$W1" '{"issue": 23}'; entry "$S4" ttyx4 tab-old-4 904 "$W2" '{"issue": 24}'
entry "$S6" ttyx6 tab-old-6 906 "$W2" '{"issue": 25}'
jq --arg s "$S1" 'map(if .session_id == $s then .issue = 26 else . end)' "$REG" > "$REG.x" && mv "$REG.x" "$REG"
issue_with 23 closed "$S3" final; issue_with 24 open "$S4" released; issue_with 25 open "$S6" stub other-run active
issue_with 26 open "$S1" parked other-run delegated
check "reopen with done issues --dry-run -> exit 0" [ "$(rc_of ts reopen --lost --dry-run)" = 0 ]
check "reopen --dry-run skips a closed issue" grep -q "^SKIP $S3: its issue test/home#23 is closed" "$T/out"
check "reopen --dry-run plans only the open ones" [ "$(grep '^PLAN ' "$T/out" | awk '{ print $2 }' | sort | tr '\n' ' ')" = "$(printf '%s\n' "$S1" "$S2" | sort | tr '\n' ' ')" ]
check "reopen with done issues -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen skips a run that was released" grep -q "^SKIP $S4: its run on test/home#24 is released" "$T/out"
check "reopen skips an issue another run took over" grep -q "^SKIP $S6: the last claim comment on test/home#25 is of another run (other-run, active)" "$T/out"
check "reopen names forget for a skipped entry" grep -qF "term.sh forget $S3 drops the entry" "$T/out"
check "reopen: the skipped ones are not launched" [ -z "$(launched "$S3")$(launched "$S4")$(launched "$S6")" ]
check "reopen: the skipped ones stay lost" [ "$(jq -c --arg a "$S3" --arg b "$S6" '[.[] | select(.session_id == $a or .session_id == $b) | .lost != null]' "$REG")" = '[true,true]' ]
check "reopen: an open issue with its own parked run (a later hand-off note) is reopened" grep -q "^REOPENED $S1 " "$T/out"
reboot; GH_STUB_FAIL_MATCH='issues/21' rc_of ts reopen --lost >/dev/null
check "reopen: an issue that cannot be read is skipped" grep -q "^SKIP $S2: cannot read test/home#21" "$T/out"
check "reopen: the unreadable one is not launched" [ -z "$(launched "$S2")" ]
check "reopen: the one without an issue is reopened" grep -q "^REOPENED $S1 " "$T/out"
reboot; hand_tab ttyx3 933 "claude --session-id $S3" "$W1"; entry "$S3" ttyx3 hand-ttyx3 933 "$W1"
ts reconcile >/dev/null 2>&1; cp "$REG" "$T/reg.before"
check "forget: a session that is not lost -> exit 3" [ "$(rc_of ts forget "$S3")" = 3 ]
check "forget: an unknown id -> exit 4" [ "$(rc_of ts forget abcdefab-0000)" = 4 ]
check "forget: two ids -> exit 2" [ "$(rc_of ts forget "$S1" "$S2")" = 2 ]
check "forget: refusals write nothing" cmp -s "$REG" "$T/reg.before"
check "forget a lost session -> exit 0" [ "$(rc_of ts forget "$S2" --reason "done by hand")" = 0 ]
check "forget prints it" out_has "FORGOTTEN $S2"
check "forget closes it with the reason, keeping its issue" [ "$(field "$S2" '"\(.closed != null) \(.closed_reason) \(.issue)"')" = "true forgotten: done by hand 21" ]
check "forget typed nothing and opened nothing" [ ! -f "$TERM_FAKE_DIR/launches" ]
rc_of ts reopen --lost >/dev/null
check "reopen after forget leaves the forgotten session" [ -z "$(launched "$S2")" ]
check "reopen after forget still reopens the other" grep -q "^REOPENED $S1 " "$T/out"
check "forget again: no open entry -> exit 4" [ "$(rc_of ts forget "$S2")" = 4 ]
check "forget clears lost and keeps where it was" [ "$(field "$S2" '"\(.lost) \(.lost_tty)"')" = "null ttyx2" ]
check "resume after forget -> exit 0" [ "$(rc_of ts resume "$S2")" = 0 ]
t2=$(field "$S2" .tty)
check "resume after forget: a live entry, not lost" [ "$(field "$S2" '"\(.lost) \(.closed)"')" = "null null" ]
check "resume after forget: state reads its tab" [ "$(rc_of ts state "$t2")" = 0 ]

# two reopen runs at once never open one session twice
reboot; ts reconcile >/dev/null 2>&1
cat > "$TERM_FAKE_DIR/on-open" <<EOF
[ -f "$TERM_FAKE_DIR/hook-ran" ] && exit 0; : > "$TERM_FAKE_DIR/hook-ran"
jq --arg s "$S2" 'map(if .session_id == \$s then . + {lost: null, tty: "ttyq2", tab: "hand-ttyq2", pid: 992} else . end)' "$REG" > "$REG.h" && mv "$REG.h" "$REG"
EOF
check "reopen while another run takes an entry over -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "reopen: the entry taken over meanwhile is skipped" grep -q "^SKIP $S2: another run reopened, adopted or closed it meanwhile" "$T/out"
check "reopen: the entry taken over meanwhile is not launched" [ -z "$(launched "$S2")" ]
check "reopen: the entry taken over keeps the other run's tab" [ "$(field "$S2" .tty)" = ttyq2 ]
reboot; ts reconcile >/dev/null 2>&1
cat > "$TERM_FAKE_DIR/on-open" <<EOF
[ -f "$TERM_FAKE_DIR/hook-ran" ] && exit 0; : > "$TERM_FAKE_DIR/hook-ran"
/bin/bash "$TERM_SH" reopen --lost > "$TERM_FAKE_DIR/nested.out" 2>&1; echo \$? > "$TERM_FAKE_DIR/nested.rc"
EOF
check "reopen with a second reopen started meanwhile -> exit 0" [ "$(rc_of ts reopen --lost)" = 0 ]
check "the second reopen exits 3" [ "$(cat "$TERM_FAKE_DIR/nested.rc")" = 3 ]
check "the second reopen names the lock" grep -q "another freeze, thaw or reopen runs" "$TERM_FAKE_DIR/nested.out"
check "each session is launched once" [ "$(launched "$S1" | wc -l | tr -d ' ')$(launched "$S2" | wc -l | tr -d ' ')" = 11 ]
check "reopen released the lock" [ ! -d "$HOME_ROOT/.local/freeze.lock" ]
rm -f "$TERM_FAKE_DIR/on-open"

# a tab that opened while the registry could not record it is named as opened, never as not opened
reboot; ts reconcile >/dev/null 2>&1
printf 'mkdir "%s"\n' "$HOME_ROOT/.local/registry.lock" > "$TERM_FAKE_DIR/on-open"
rc_of ts reopen "$S1" >/dev/null; rmdir "$HOME_ROOT/.local/registry.lock" 2>/dev/null; rm -f "$TERM_FAKE_DIR/on-open"
check "reopen: an opened tab the registry missed is named" grep -q "^FAILED $S1: a tab opened on ttyf1 but the registry could not be updated" "$T/out"
check "reopen: it is not called not opened" not grep -q "^FAILED $S1: the tab did not open" "$T/out"
check "adopt records that tab -> exit 0" [ "$(rc_of ts adopt ttyf1)" = 0 ]
check "adopt says it updated the reservation" grep -q "^UPDATED ttyf1 $S1" "$T/out"
check "the one entry names that tab now" [ "$(jq -c --arg s "$S1" '[.[] | select(.session_id == $s) | [.tty, .pid, .lost, .closed]]' "$REG")" = '[["ttyf1",60001,null,null]]' ]

# ---------------------------------------------------------------- text survey
# a registered Codex tab names its pid and id; an unregistered one stays a shell line
reset; hand_tab ttyc1 741 "/opt/bin/codex" "$W1"; entry "$S1" ttyc1 hand-ttyc1 741 "$W1" '{"kind": "codex", "match": "/opt/bin/codex"}'
hand_tab ttyc2 742 "/opt/bin/codex" "$W2"
check "survey: a registered Codex tab shows its pid and id" [ "$(ts survey | grep '^ttyc1 ')" = "ttyc1 741 codex $S1 $W1" ]
check "survey: an unregistered Codex tab stays a shell line" [ "$(ts survey | grep '^ttyc2 ')" = "ttyc2 - shell - $W2" ]
# a long process list with SIGPIPE ignored: no write error from a reader that stops early
reset; live ttys1 751 "$W1" "$S1"
for i in 1 2 3 4 5 6; do
  mkdir -p "$TERM_FAKE_DIR/proc/77$i"; printf ttyzz > "$TERM_FAKE_DIR/proc/77$i/tty"
  head -c 40000 /dev/zero | tr '\0' x > "$TERM_FAKE_DIR/proc/77$i/cmd"
done
( trap '' PIPE; ts survey >/dev/null 2>"$T/err" )
check "survey: no broken-pipe noise on a long process list" not grep -q "Broken pipe" "$T/err"

# ---------------------------------------------------------------- helpers off
reboot; sed -i.bak 's/^terminal_helpers=on$/terminal_helpers=off/' "$HOME_ROOT/.local/config"; rm -f "$HOME_ROOT/.local/config.bak"
for v in reconcile "adopt ttyx1" "reopen --lost" regroup; do
  check "helpers off: $v -> exit 3" [ "$(rc_of ts $v)" = 3 ]
done
check "helpers off: nothing launched" [ ! -f "$TERM_FAKE_DIR/launches" ]

# ---------------------------------------------------------------- regroup
reset
live ttyr1 801 "$W1" "$S1" w1; live ttyr2 802 "$W1" "$S2" w1; live ttyr3 803 "$W1" "$S3" w2; live ttyr4 804 "$W2" "$S4" w2
hand_tab ttyr5 805 "claude --resume $S5" "$W1" w3
ts adopt ttyr1 ttyr2 ttyr3 ttyr4 >/dev/null 2>&1
cp "$REG" "$T/reg.before"
check "regroup --dry-run -> exit 0" [ "$(rc_of ts regroup --dry-run)" = 0 ]
check "regroup: the plan moves the g1 tab out of w2" [ "$(cat "$T/out")" = "MOVE ttyr3 $S3 group g1: window w2 -> w1" ]
check "regroup: a tab not registered is not planned" not grep -q ttyr5 "$T/out"
check "regroup without --dry-run -> exit 3 (unsupported)" [ "$(rc_of ts regroup)" = 3 ]
check "regroup says nothing was moved" grep -q "nothing was moved" "$T/err"
check "regroup moved nothing" [ "$(cat "$(tabdir ttyr3)/window")" = w2 ]
check "regroup typed nothing and wrote nothing" nokeys ttyr1 ttyr2 ttyr3 ttyr4
check "regroup left the registry" cmp -s "$REG" "$T/reg.before"
printf w1 > "$(tabdir ttyr3)/window"
check "regroup: all in place -> exit 0" [ "$(rc_of ts regroup)" = 0 ]
check "regroup: says so" grep -q "every registered tab is in its group's window" "$T/out"
# a window shared with sessions of another group that stay there is no group's window
reset
live ttyr1 801 "$W1" "$S1" w1; hand_tab ttyr2 802 "claude --model opus" "$W2" w1
ts adopt ttyr1 >/dev/null 2>&1
check "regroup shared: --dry-run -> exit 0" [ "$(rc_of ts regroup --dry-run)" = 0 ]
check "regroup shared: the g1 tab goes to a new window" [ "$(cat "$T/out")" = "MOVE ttyr1 $S1 group g1: window w1 -> new (window w1 also holds g2)" ]
check "regroup shared: the tab this home did not open is not planned" not grep -q ttyr2 "$T/out"
reset; live ttyr1 801 "$W1" "$S1" w1; hand_tab ttyr2 802 "-zsh" "$W2" w1 shell
ts adopt ttyr1 >/dev/null 2>&1
check "regroup shared: a plain shell tab does not count" [ "$(rc_of ts regroup --dry-run; cat "$T/out")" = "0
every registered tab is in its group's window" ]

echo "recover.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
