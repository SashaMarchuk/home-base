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
  mkdir -p "$TERM_FAKE_DIR/proc/$(($2 + 5000))"   # the tab's own login shell, as a real tab has
  printf '%s' -zsh > "$TERM_FAKE_DIR/proc/$(($2 + 5000))/cmd"; printf '%s' "$1" > "$TERM_FAKE_DIR/proc/$(($2 + 5000))/tty"
  printf '%s' "$4" > "$TERM_FAKE_DIR/proc/$(($2 + 5000))/cwd"
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
for f in "$SESS" "$ROOT/scripts/term/freeze.sh" "$ROOT/scripts/term/thaw.sh"; do
  check "${f##*/} has no temp/user paths" lint_paths "$f"
  check "${f##*/} has no underscore functions" lint_underscore "$f"
done
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
check "identity: default survey still reads codex as shell" [ "$(ts survey)" = "ttya1 - shell - $W1" ]

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
check "caller: no signal -> no caller" [ "$(ts survey --json | jq -sc '[(map(.tty) | sort | join(" ")), (map(select(.caller)) | length)]')" = '["ttyc1 ttyc2",0]' ]
check "caller: an id with no session file -> no caller" [ "$(CLAUDE_CODE_SESSION_ID=$S4 ts survey --json | jq -sc '[(map(.tty) | sort | join(" ")), (map(select(.caller)) | length)]')" = '["ttyc1 ttyc2",0]' ]

# ---------------------------------------------------------------- groups and windows
GRPS="term.groups=g1,g2,wide"
GKEYS=("$GRPS" "term.group.g1.cwd=$W1" "term.group.g2.cwd=$W2" "term.group.wide.cwd=$T/work")
opened() { ts open "$@" | awk '{ print $2 }'; }   # opened <open args> -> the new tab's tty
win_of() { cat "$(tabdir "$1")/window"; }
reset "${GKEYS[@]}"
hand_tab ttyg1 701 "claude" "$W1" w7; sess_file work 701 "$S1" idle "$W1"
hand_tab ttyg2 702 "claude" "$W2" w8; sess_file work 702 "$S2" idle "$W2"
t=$(opened "$W1/sub")
check "groups: a g1 folder opens in the window holding the live g1 tab" [ "$(win_of "$t")" = w7 ]
check "groups: group and window recorded" [ "$(jq -r --arg t "$t" '.[] | select(.tty == $t) | .group + " " + .window' "$REG")" = "g1 w7" ]
t=$(opened "$W2")
check "groups: the longest prefix wins (g2, not wide)" [ "$(win_of "$t")" = w8 ]
t=$(opened "$W1" --group g2)
check "groups: --group beats the folder" [ "$(win_of "$t")" = w8 ]
check "groups: survey reads the recorded group" [ "$(sj "$t" | jq -r '.group + " " + .group_from')" = "g2 explicit" ]
check "groups: survey derives the group from the folder" [ "$(sj ttyg1 | jq -r '.group + " " + .group_from')" = "g1 cwd" ]
hand_tab ttyg3 703 "claude" "$T" w9
check "groups: no matching folder -> general by fallback" [ "$(sj ttyg3 | jq -r '.group + " " + .group_from')" = "general fallback" ]
t=$(opened "$T/work")
check "groups: no live tab of the group -> a new window" grep -qx "$(win_of "$t")" "$TERM_FAKE_DIR/windows"
check "groups: the new window is cached" [ "$(jq -r '.[] | select(.group == "wide") | .window' "$HOME_ROOT/.local/windows.json")" = "$(win_of "$t")" ]
reset "${GKEYS[@]}"
printf '[{"group": "g1", "window": "w5", "created": "x"}]\n' > "$HOME_ROOT/.local/windows.json"
hand_tab ttys5 705 "zsh" "$WX" w5 shell
t=$(opened "$W1")
check "groups: the cached window is reused while it holds no other group's tab" [ "$(win_of "$t")" = w5 ]
reset "${GKEYS[@]}"
printf '[{"group": "g1", "window": "w5", "created": "x"}]\n' > "$HOME_ROOT/.local/windows.json"
hand_tab ttyg2 702 "claude" "$W2" w5; sess_file work 702 "$S2" idle "$W2"
t=$(opened "$W1")
check "groups: a cached window that now holds a g2 tab is not reused for g1" [ "$(win_of "$t")" != w5 ]
check "groups: a new window was created instead" grep -qx "$(win_of "$t")" "$TERM_FAKE_DIR/windows"
reset "${GKEYS[@]}"
check "groups: an unknown group -> exit 2" [ "$(rc_of ts open "$W1" --group nope)" = 2 ]
check "groups: nothing launched for an unknown group" [ ! -f "$TERM_FAKE_DIR/launches" ]
reset
printf 'w3' > "$TERM_FAKE_DIR/front-window"
t=$(opened "$W1")
check "groups: without term.groups the current window is used" [ "$(win_of "$t")" = w3 ]
check "groups: without term.groups no window is cached" [ ! -f "$HOME_ROOT/.local/windows.json" ]
reset
cp "$HOME_ROOT/home.config" "$T/hc.bak"
printf '%s\n' "$GRPS" "term.group.g1.cwd=$W1" >> "$HOME_ROOT/home.config"
printf 'w3' > "$TERM_FAKE_DIR/front-window"
t=$(opened "$W1")
check "groups: group keys in home.config are ignored" [ "$(win_of "$t")" = w3 ]
check "groups: an unknown group from home.config -> exit 2" [ "$(rc_of ts open "$W1" --group g1)" = 2 ]
cp "$T/hc.bak" "$HOME_ROOT/home.config"

# ---------------------------------------------------------------- freeze --hard
FKEYS=("${GKEYS[@]}" "term.group.g2.home=peer" term.freeze.hard_grace=1 launch.profile_flag=-p)
live() { # live <tty> <pid> <cwd> <window> <session id> [status]: a Claude Code tab with its session file
  hand_tab "$1" "$2" "claude --model opus" "$3" "$4"; sess_file work "$2" "$5" "${6:-idle}" "$3" "name-$1"
}
fdialog() { # fdialog <tty> <question> [sticky]
  printf 'Header\n%s\n  1. Yes\n  2. No\nEnter to select · Esc to cancel\n' "$2" > "$(tabdir "$1")/dialog"
  [ -n "${3:-}" ] && : > "$(tabdir "$1")/sticky-dialog"
  # the session reports idle once its dialog is gone (as Claude Code updates its session file)
  cat > "$(tabdir "$1")/on-key" <<EOF
#!/bin/bash
[ -f "$(tabdir "$1")/dialog" ] && exit 0
f="$TERM_FAKE_DIR/profiles/work/sessions/$(cat "$(tabdir "$1")/pid").json"
jq '.status = "idle"' "\$f" > "\$f.x" && mv "\$f.x" "\$f"
EOF
  return 0
}
issue_text() { # issue_text <owner/repo>: every issue body and comment in the gh stub for that repo
  local d="$GH_STUB_DIR/${1%%/*}__${1#*/}/issues"
  [ -d "$d" ] || return 0
  cat "$d"/*.json | jq -r '.title, .body, (.comments[]?.body)'
}
no_leak() { ! issue_text "$1" | grep -qF -- "$2"; }   # no_leak <repo> <text>: the text is nowhere in that repo's issues
snapf() { ls "$HOME_ROOT/.local/freeze/"*.json 2>/dev/null | head -1; }
outcome() { jq -r --arg t "$1" '.entries[] | select(.tty == $t) | .outcome' "$(snapf)"; }
nokeys() { local t; for t in "$@"; do [ -z "$(keys "$t")" ] || return 1; done; }
QP="Deploy the peer plan now?"; QU="Unmapped question text here?"
setup_main() {
  reset "${FKEYS[@]}"
  live ttyw1 801 "$W1" w7 "$S1"
  live ttyw2 802 "$W2" w8 "$S2" waiting; fdialog ttyw2 "$QP"
  live ttyw3 803 "$T" w9 "$S3" waiting; fdialog ttyw3 "$QU"
  hand_tab ttyw4 804 "/opt/bin/codex" "$W1" w7
  hand_tab ttyw5 805 "-zsh" "$W1" w7 shell
}
setup_main
: > "$T/marker"; sleep 1
check "freeze: --all --hard exits 0" [ "$(rc_of ts freeze --all --hard)" = 0 ]
check "freeze: the idle g1 tab exited" [ "$(outcome ttyw1)" = exited ]
check "freeze: the dialog tabs exited after one Esc each" [ "$(outcome ttyw2) $(outcome ttyw3)" = "exited exited" ]
check "freeze: one Esc on each dialog" [ "$(keys ttyw2 | grep -c key:esc) $(keys ttyw3 | grep -c key:esc)" = "1 1" ]
check "freeze: no dialog answered" [ ! -f "$(tabdir ttyw2)/answered" ]
check "freeze: no dialog answered (second half)" [ ! -f "$(tabdir ttyw3)/answered" ]
check "freeze: /exit typed into the closed tabs" [ "$(sent ttyw1 | head -1)" = /exit ]
check "freeze: their processes are gone" not alive 801
check "freeze: codex and shell tabs listed, not touched" [ "$(outcome ttyw4) $(outcome ttyw5)" = "kept:not-claude kept:not-claude" ]
check "freeze: no key in the codex or shell tab" nokeys ttyw4 ttyw5
check "freeze: nothing signalled" [ ! -f "$TERM_FAKE_DIR/kills" ]
check "freeze: the snapshot keeps the dialog question and options" \
  [ "$(jq -r --arg t ttyw3 '.entries[] | select(.tty == $t) | .question + " | " + (.options | join(","))' "$(snapf)")" = "Header $QU | 1. Yes,2. No" ]
check "freeze: one freeze issue in this home" [ "$(ls "$GH_STUB_DIR/test__home/issues" | wc -l | tr -d ' ')" = 1 ]
check "freeze: one freeze issue in the peer home" [ "$(ls "$GH_STUB_DIR/test__peer/issues" | wc -l | tr -d ' ')" = 1 ]
check "freeze: this home's issue lists the g1 session with its resume line" grep -qF -- "-p 'work' --model 'opus' --resume $S1" <(issue_text test/home)
check "freeze: the freeze issues are parked" [ "$(cat "$GH_STUB_DIR"/test__*/issues/*.json | jq -r '.labels | index("status:parked") != null' | sort -u)" = true ]
check "freeze: the peer question is in the peer home's issue" grep -qF -- "$QP" <(issue_text test/peer)
check "boundary: the peer question never enters this home's issue" no_leak test/home "$QP"
check "boundary: an unmapped tab's question never enters this home's issue" no_leak test/home "$QU"
check "boundary: an unmapped tab's folder never enters this home's issue" not grep -qF "name-ttyw3" <(issue_text test/home)
check "boundary: the unmapped tab is a pointer line" grep -qF -- "$S3: unmapped tab" <(issue_text test/home)
cp -R "$GH_STUB_DIR/test__home" "$GH_STUB_DIR/test__leak"
f=$(ls "$GH_STUB_DIR/test__leak/issues/"*.json | head -1)
jq --arg q "$QU" '.comments += [{id: 99, body: ("open question: " + $q)}]' "$f" > "$f.x" && mv "$f.x" "$f"
check "boundary: the check fails when an unmapped question is in this home's issue" not no_leak test/leak "$QU"
check "freeze: adopted tabs recorded, closed and frozen" [ "$(jq -r '[.[] | select(.adopted and .closed != null and .frozen != null)] | length' "$REG")" = 3 ]
check "freeze: the lock is released" [ ! -d "$HOME_ROOT/.local/freeze.lock" ]
written_outside() { # every file the freeze wrote outside this home's .local (the fake, the gh stub and the test's own logs aside)
  find "$T" -newer "$T/marker" -type f ! -path "$HOME_ROOT/.local/*" ! -path "$TERM_FAKE_DIR/*" ! -path "$GH_STUB_DIR/*" \
    ! -path "$T/check.log" ! -path "$T/out" ! -path "$T/err"
}
check "freeze: every file it wrote is under this home's .local" [ -z "$(written_outside)" ]
: > "$T/stray"
check "freeze: the .local check catches a stray file" [ -n "$(written_outside)" ]
rm -f "$T/stray"

# snapshot and record before the first key
setup_main
cat > "$TERM_FAKE_DIR/on-first-key" <<EOF
#!/bin/bash
ls "$HOME_ROOT/.local/freeze/"*.json >/dev/null 2>&1 || exit 0
cat "$GH_STUB_DIR"/test__home/issues/*.json 2>/dev/null | jq -r .body | grep -q '<!-- freeze-data ' || exit 0
echo before > "$T/order"
EOF
ts freeze --all --hard >/dev/null 2>&1
check "snapshot first: snapshot and the record read back exist before the first key in any tab" [ "$(cat "$T/order" 2>/dev/null)" = before ]
check "snapshot first: the first key was an Esc (a dialog tab), so the check covered every tab" [ -f "$TERM_FAKE_DIR/first-key-seen" ]
rm -f "$T/order"
setup_main
check "snapshot first: a failing record -> exit 0 with nothing closed" [ "$(GH_STUB_FAIL_MATCH='title=Freeze' rc_of ts freeze --all --hard)" = 0 ]
check "snapshot first: no key in any tab when the record failed" nokeys ttyw1 ttyw2 ttyw3 ttyw4 ttyw5
check "snapshot first: the tabs are kept with kept:no-record" [ "$(outcome ttyw1) $(outcome ttyw2)" = "kept:no-record kept:no-record" ]

# the calling session
setup_main
mkdir -p "$TERM_FAKE_DIR/proc/850"; printf 'bash term.sh' > "$TERM_FAKE_DIR/proc/850/cmd"; printf 'ttyw1' > "$TERM_FAKE_DIR/proc/850/tty"
printf '801' > "$TERM_FAKE_DIR/proc/850/ppid"; printf '850' > "$TERM_FAKE_DIR/self-pid"
ts freeze --all --hard >/dev/null 2>&1
check "caller: left open, no key" nokeys ttyw1
check "caller: recorded as kept:caller" [ "$(outcome ttyw1)" = kept:caller ]
check "caller: its row and resume line are in the issue" grep -qF -- "caller (left open)" <(issue_text test/home)
check "caller: the others were closed" [ "$(outcome ttyw2)" = exited ]
setup_main
check "caller: inside a session whose tab is not found -> --all exits 3" [ "$(CLAUDE_CODE_SESSION_ID=$S4 rc_of ts freeze --all --hard)" = 3 ]
check "caller: nothing touched" nokeys ttyw1 ttyw2 ttyw3
check "caller: no snapshot written" [ -z "$(snapf)" ]
check "caller: explicit targets still allowed" [ "$(CLAUDE_CODE_SESSION_ID=$S4 rc_of ts freeze ttyw1 --hard)" = 0 ]

# non-claude tabs and sessions that cannot be reopened
setup_main
check "non-claude: a selector naming only a codex tab -> exit 3" [ "$(rc_of ts freeze ttyw4 --hard)" = 3 ]
check "non-claude: nothing typed" nokeys ttyw4
reset "${FKEYS[@]}"; hand_tab ttym1 811 "claude -r" "$W1" w7
check "resume manual: a session with no id -> exit 3" [ "$(rc_of ts freeze --all --hard)" = 3 ]
check "resume manual: never typed into" nokeys ttym1
reset "${FKEYS[@]}"; hand_tab ttym1 811 "claude -r" "$W1" w7; live ttyw1 801 "$W1" w7 "$S1"
ts freeze --all --hard >/dev/null 2>&1
check "resume manual: kept as kept:no-resume beside a closed tab" [ "$(outcome ttym1) $(outcome ttyw1)" = "kept:no-resume exited" ]

# drafts, a running turn, a dialog that stays, signals that disagree
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; printf 'half written thought' > "$(tabdir ttyw1)/box"
ts freeze --all --hard >/dev/null 2>&1
check "draft: kept as kept:draft" [ "$(outcome ttyw1)" = kept:draft ]
check "draft: only the probe and its backspace" [ "$(keys ttyw1 | tr '\n' ' ')" = "type:x key:bs " ]
check "draft: text kept" [ "$(cat "$(tabdir ttyw1)/box")" = "half written thought" ]
reset "${FKEYS[@]}" term.freeze.drafts=save; live ttyw1 801 "$W1" w7 "$S1"; printf 'half written thought' > "$(tabdir ttyw1)/box"
ts freeze --all --hard >/dev/null 2>&1
check "draft: a hand-written drafts=save still keeps the tab" [ "$(outcome ttyw1) $(cat "$(tabdir ttyw1)/box")" = "kept:draft half written thought" ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; put_ghost() { printf 'run the tests' > "$(tabdir ttyw1)/ghost"; }; put_ghost
ts freeze --all --hard >/dev/null 2>&1
check "suggestion: cleared and closed" [ "$(outcome ttyw1)" = exited ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
ts freeze --all --hard >/dev/null 2>&1
check "busy: kept running as kept:busy" [ "$(outcome ttyw1)" = kept:busy ]
check "busy: never interrupted (no Esc, no key)" nokeys ttyw1
reset "${FKEYS[@]}" term.freeze.busy=interrupt; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
ts freeze --all --hard >/dev/null 2>&1
check "busy: a hand-written busy=interrupt still never interrupts" nokeys ttyw1
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" waiting; fdialog ttyw1 "Pick one?" sticky
ts freeze --all --hard >/dev/null 2>&1
check "dialog: a dialog that stays open keeps the tab" [ "$(outcome ttyw1)" = kept:dialog ]
check "dialog: one Esc only, no option" [ "$(keys ttyw1 | tr '\n' ' ')" = "key:esc " ]
check "dialog: one Esc only, no option (second half)" [ ! -f "$(tabdir ttyw1)/answered" ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy
ts freeze --all --hard >/dev/null 2>&1
check "two signals: an idle screen with a busy session file is not typed into" [ "$(outcome ttyw1)" = kept:signals-disagree ]
check "two signals: no key" nokeys ttyw1

# selectors
setup_main
ts freeze --group g1 --hard >/dev/null 2>&1
check "selector: --group g1 picks only the g1 tabs" [ "$(jq -r '[.entries[].tty] | join(" ")' "$(snapf)")" = ttyw1 ]
setup_main
ts freeze --window w8 --hard >/dev/null 2>&1
check "selector: --window w8 picks only that window" [ "$(jq -r '[.entries[].tty] | join(" ")' "$(snapf)")" = ttyw2 ]
setup_main
ts freeze ttyw1 "$S3" --hard >/dev/null 2>&1
check "selector: a tty and a session id pick exactly those" [ "$(jq -r '[.entries[].tty] | sort | join(" ")' "$(snapf)")" = "ttyw1 ttyw3" ]
setup_main
ts freeze --all --hard --except ttyw2 >/dev/null 2>&1
check "selector: --except keeps that tab" [ "$(outcome ttyw2)" = kept:except ] && nokeys ttyw2
setup_main
check "selector: an unknown group -> exit 2" [ "$(rc_of ts freeze --group nope --hard)" = 2 ]
check "selector: an unknown window -> exit 2" [ "$(rc_of ts freeze --window w99 --hard)" = 2 ]
check "selector: an unknown tty -> exit 4" [ "$(rc_of ts freeze ttynone --hard)" = 4 ]
check "selector: a title -> exit 2" [ "$(rc_of ts freeze my-tab --hard)" = 2 ]
check "selector: nothing touched by the refusals" nokeys ttyw1 ttyw2 ttyw3
check "selector: no snapshot from the refusals" [ -z "$(snapf)" ]
out=$(ts freeze --all --hard --dry-run)
check "dry run: prints the plan" grep -q '^ttyw2 g2 dialog -> hard close$' <<<"$out"
check "dry run: touches nothing" nokeys ttyw1 ttyw2 ttyw3
check "dry run: writes nothing" [ -z "$(snapf)" ]
check "dry run: writes nothing (second half)" [ ! -d "$GH_STUB_DIR/test__home" ]

# lock and linger
setup_main
mkdir -p "$HOME_ROOT/.local/freeze.lock"
check "lock: a second freeze -> exit 3" [ "$(rc_of ts freeze --all --hard)" = 3 ]
check "lock: nothing typed" nokeys ttyw1 ttyw2
check "lock: not stolen" [ -d "$HOME_ROOT/.local/freeze.lock" ]
rmdir "$HOME_ROOT/.local/freeze.lock"
check "lock: a freeze after the first one ended runs" [ "$(rc_of ts freeze ttyw1 --hard)" = 0 ]
check "lock: and the next one too" [ "$(rc_of ts freeze ttyw3 --hard)" = 0 ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; : > "$(tabdir ttyw1)/linger"
check "linger: a PID that survives /exit -> exit 5" [ "$(rc_of ts freeze --all --hard)" = 5 ]
check "linger: kept:linger, nothing signalled" [ "$(outcome ttyw1)" = kept:linger ]
check "linger: kept:linger, nothing signalled (second half)" [ ! -f "$TERM_FAKE_DIR/kills" ]

# continue, and a tab bound to an issue
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
ts freeze --all --hard >/dev/null 2>&1
id=$(jq -r .id "$(snapf)")
rm -f "$(tabdir ttyw1)/busy"; sess_file work 801 "$S1" idle "$W1"
check "continue: picks up a tab that was busy" [ "$(rc_of ts freeze --continue "$id")" = 0 ]
check "continue: it is closed now" [ "$(outcome ttyw1)" = exited ]
check "continue: one record only" [ "$(ls "$GH_STUB_DIR/test__home/issues" | wc -l | tr -d ' ')" = 1 ]
reset "${FKEYS[@]}"
mkdir -p "$GH_STUB_DIR/test__home/issues"
o=$(ts open "$W1" --issue 31); osid=${o%% *}; otty=$(echo "$o" | awk '{ print $2 }'); opid=${o##* }
sess_file work "$opid" "$osid" idle "$W1"; claim 31 "$osid"
ts freeze "$otty" --hard >/dev/null 2>&1
check "issue-bound: the tab's own issue gets the park checkpoint" grep -qF "Frozen by term.sh" <(issue_text test/home)
check "issue-bound: and it closed" [ "$(outcome "$otty")" = exited ]

# ---------------------------------------------------------------- thaw
frozen_main() { # three closed sessions (g1, g2 with a question, an unmapped one) and their transcripts
  setup_main
  ts freeze --all --hard >/dev/null 2>&1
  transcript work "$S1"; transcript work "$S2"; transcript work "$S3"
  FROZEN=$(jq -r .id "$(snapf)")
}
launch_of() { grep -F -- "--resume $1" "$TERM_FAKE_DIR/launches"; }
tty_of() { jq -r --arg s "$1" '.entries[] | select(.session_id == $s) | .thaw_tty // empty' "$(snapf)"; }
frozen_main
check "thaw: latest reopens the frozen sessions" [ "$(rc_of ts thaw latest)" = 0 ]
check "thaw: three sessions reopened" [ "$(jq '[.entries[] | select(.thaw_outcome == "reopened")] | length' "$(snapf)")" = 3 ]
check "thaw: same session id with the profile and model" grep -qF -- "&& 'claude' -p 'work' --model 'opus' --resume $S1 'You were resumed. Continue where you stopped.'" <(launch_of "$S1")
check "thaw: an open question is re-asked" grep -qF -- "Re-ask your open question with the ask tool" <(launch_of "$S2")
check "thaw: the g1 and g2 sessions open in different windows" [ "$(win_of "$(tty_of "$S1")")" != "$(win_of "$(tty_of "$S2")")" ]
check "thaw: windows cached per group" [ "$(jq -r '[.[].group] | sort | join(" ")' "$HOME_ROOT/.local/windows.json")" = "g1 g2 general" ]
check "thaw: nothing typed after the launch line" nokeys "$(tty_of "$S1")" "$(tty_of "$S2")"
check "thaw: every reopened tab started with its command" [ "$(grep -c -- "-lic 'eval " "$TERM_FAKE_DIR/commands")" = 3 ]
check "thaw: the peer freeze issue is finished" [ "$(cat "$GH_STUB_DIR"/test__peer/issues/*.json | jq -r .state)" = closed ]
check "thaw: a second thaw reopens nothing" [ "$(ts thaw latest | grep -c REOPENED)" = 0 ]
frozen_main
live ttyz1 901 "$W1" w7 "$S1"
rm -f "$TERM_FAKE_DIR/profiles/work/projects/p/$S3.jsonl"
out=$(ts thaw latest)
check "thaw: a session live already is skipped" grep -q "^SKIP $S1: it is live already" <<<"$out"
check "thaw: never launched twice" [ -z "$(launch_of "$S1")" ]
check "thaw: a missing transcript is skipped with its resume line" grep -q "^SKIP $S3: its transcript is not on this machine; resume it where it is: cd " <<<"$out"
check "thaw: the rest reopened" grep -q "^REOPENED $S2 " <<<"$out"
check "thaw: the freeze issue stays open while sessions are left" [ "$(cat "$GH_STUB_DIR"/test__home/issues/*.json | jq -r .state)" = open ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"; live ttyw2 802 "$W1" w7 "$S2"
ts freeze --all --hard >/dev/null 2>&1; transcript work "$S1"; transcript work "$S2"
rm -rf "$(tabdir ttyw1)" "$TERM_FAKE_DIR/proc/801" "$TERM_FAKE_DIR/proc/5801"   # the kept tab was closed by hand later
out=$(ts thaw latest)
check "thaw: an entry that was not closed is skipped" grep -q "^SKIP $S1: it was not closed (kept:busy)" <<<"$out"
check "thaw: an entry that was not closed is never launched" [ -z "$(launch_of "$S1")" ]
frozen_main
printf '5' > "$TERM_FAKE_DIR/mem_free"
check "thaw: low memory stops the run (exit 3)" [ "$(rc_of ts thaw latest)" = 3 ]
check "thaw: it reports what is left and how to continue" grep -q "3 left; run 'term.sh thaw --continue $FROZEN' later" "$T/out"
check "thaw: nothing opened under memory pressure" [ ! -f "$TERM_FAKE_DIR/launches" ]
rm -f "$TERM_FAKE_DIR/mem_free"
check "thaw: --continue reopens the rest" [ "$(ts thaw --continue "$FROZEN" | grep -c REOPENED)" = 3 ]
frozen_main
check "thaw: --group g2 reopens only that group" [ "$(ts thaw latest --group g2 | grep -c REOPENED)" = 1 ]
check "thaw: --group g2 reopens only that group (second half)" [ -z "$(launch_of "$S1")" ]
check "thaw: an unknown group -> exit 2" [ "$(rc_of ts thaw latest --group nope)" = 2 ]
frozen_main
mv "$(snapf)" "$T/snap.bak"
out=$(ts thaw --issue test/home#1)
check "thaw: from the issue when the snapshot is gone" grep -q "^REOPENED $S1 " <<<"$out"
check "thaw: an unmapped tab is not reopened from the issue" grep -q "^KEPT $S3: unmapped tab" <<<"$out"
reset "${FKEYS[@]}"
check "thaw: no snapshot -> exit 4" [ "$(rc_of ts thaw latest)" = 4 ]

# ---------------------------------------------------------------- freeze --soft and --soft-then-hard
answers() { # answers <tty> [nonce|wrong] [status]: the session writes its checkpoint when the soft prompt arrives
  cat > "$(tabdir "$1")/on-submit" <<EOF
#!/bin/bash
case "\$1" in "Freeze "*": pause now."*) ;; *) exit 0 ;; esac
p=\$(printf '%s' "\$1" | sed -n 's/.* Write \(.*\) with the headings: .*/\1/p')
n=\$(printf '%s' "\$1" | sed -n 's/.*last line exactly: nonce: \([^.]*\)\..*/\1/p')
[ "${2:-}" = wrong ] && n=other
printf '# What this session is\nwork on the g1 project\n# Open questions for the owner (verbatim)\nCheckpoint question $1?\nnonce: %s\n' "\$n" > "\$p"
f="$TERM_FAKE_DIR/profiles/work/sessions/$(cat "$(tabdir "$1")/pid").json"
jq '.status = "${3:-idle}"' "\$f" > "\$f.x" && mv "\$f.x" "\$f"
EOF
}
SKEYS=("${FKEYS[@]}" term.freeze.soft_timeout=1)
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; answers ttyw1
check "soft: --soft exits 0" [ "$(rc_of ts freeze --all --soft)" = 0 ]
check "soft: the prompt was the first thing typed" [ "$(sent ttyw1 | head -1 | cut -c1-40)" = "$(printf 'Freeze %s: pause now. Do not ask t' "$(jq -r .id "$(snapf)")" | cut -c1-40)" ]
check "soft: /exit after the checkpoint with the right nonce" [ "$(sent ttyw1 | sed -n 2p)" = /exit ]
check "soft: closed" [ "$(outcome ttyw1)" = exited ]
check "soft: the checkpoint is under this home's .local" [ -f "$HOME_ROOT/.local/freeze/$(jq -r .id "$(snapf)")/$S1.md" ]
check "soft: the checkpoint is copied into the freeze issue without the nonce" grep -qF -- "Checkpoint question ttyw1?" <(issue_text test/home)
check "soft: no nonce line in the issue" not grep -q '^nonce: ' <(issue_text test/home)
transcript work "$S1"
ts thaw latest >/dev/null 2>&1
check "soft: thaw asks it to read its checkpoint first" grep -qF -- "Read $HOME_ROOT/.local/freeze/" <(launch_of "$S1")
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"
ts freeze --all --soft >/dev/null 2>&1
check "soft: only the prompt's echo, no file -> no /exit" [ "$(sent ttyw1 | grep -c '^/exit$')" = 0 ]
check "soft: kept:soft-timeout, the session runs" [ "$(outcome ttyw1)" = kept:soft-timeout ] && alive 801
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; answers ttyw1 wrong
ts freeze --all --soft >/dev/null 2>&1
check "soft: a file with a wrong nonce -> no /exit" [ "$(sent ttyw1 | grep -c '^/exit$')" = 0 ]
check "soft: a file with a wrong nonce -> no /exit (second half)" [ "$(outcome ttyw1)" = kept:soft-timeout ]
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; answers ttyw1 nonce busy
ts freeze --all --soft >/dev/null 2>&1
check "soft: the right nonce but a session not idle -> no /exit" [ "$(sent ttyw1 | grep -c '^/exit$')" = 0 ]
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
ts freeze --all --soft >/dev/null 2>&1
check "soft: never typed into a running turn" nokeys ttyw1
check "soft: kept:soft-timeout" [ "$(outcome ttyw1)" = kept:soft-timeout ]
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" waiting; fdialog ttyw1 "Pick?"
ts freeze --all --soft >/dev/null 2>&1
check "soft: a dialog is never answered or cancelled by soft" nokeys ttyw1
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"
ts freeze --all >/dev/null 2>&1
check "default mode: soft first" [ "$(sent ttyw1 | head -1 | cut -c1-7)" = "Freeze " ]
check "default mode: then hard for a tab that did not answer" [ "$(outcome ttyw1)" = exited ]
check "default mode: then hard for a tab that did not answer (second half)" [ "$(sent ttyw1 | sed -n 2p)" = /exit ]
reset "${SKEYS[@]}" term.freeze.default_mode=hard; live ttyw1 801 "$W1" w7 "$S1"
ts freeze --all >/dev/null 2>&1
check "default mode: term.freeze.default_mode=hard types no soft prompt" [ "$(sent ttyw1 | head -1)" = /exit ]
reset "${SKEYS[@]}" term.freeze.default_mode=fast; live ttyw1 801 "$W1" w7 "$S1"
check "default mode: an invalid term.freeze.default_mode -> exit 3" [ "$(rc_of ts freeze --all)" = 3 ]
check "default mode: nothing typed for an invalid mode" nokeys ttyw1
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
ts freeze --all --soft-then-hard >/dev/null 2>&1
check "soft-then-hard: a running turn stays running after both" [ "$(outcome ttyw1)" = kept:busy ] && nokeys ttyw1
reset "${SKEYS[@]}"
live ttyw2 802 "$W2" w8 "$S2"; answers ttyw2
live ttyw3 803 "$T" w9 "$S3"; answers ttyw3
ts freeze --all --soft >/dev/null 2>&1
check "soft boundary: the peer tab's checkpoint goes to the peer issue" grep -qF -- "Checkpoint question ttyw2?" <(issue_text test/peer)
check "soft boundary: an unmapped tab's checkpoint never enters this home's issue" no_leak test/home "Checkpoint question ttyw3?"
check "soft boundary: the peer checkpoint never enters this home's issue" no_leak test/home "Checkpoint question ttyw2?"

# ---------------------------------------------------------------- review fixes
# the selector of the tabs this home opened (registered, not adopted): never the owner's own tabs
OWNSEL='select(.registered and (.adopted | not) and (.role == "worker" or .role == "orchestrator")) | .tty'
reset "${FKEYS[@]}"
live ttyw1 801 "$W1" w7 "$S1"
ts freeze ttyw1 --hard >/dev/null 2>&1; transcript work "$S1"; ts thaw latest >/dev/null 2>&1
o=$(ts open "$W1"); wtty=$(echo "$o" | awk '{ print $2 }')
check "limits selector: a worker this home opened is picked" [ "$(ts survey --json | jq -r "$OWNSEL")" = "$wtty" ]
check "limits selector: the owner's thawed tab is registered but not picked" [ "$(ts survey --json | jq -r 'select(.registered and .adopted) | .tty' | wc -l | tr -d ' ')" = 1 ]
# thaw finishes the freeze issue when the only session left is the live caller
setup_main
mkdir -p "$TERM_FAKE_DIR/proc/850"; printf 'bash term.sh' > "$TERM_FAKE_DIR/proc/850/cmd"; printf 'ttyw1' > "$TERM_FAKE_DIR/proc/850/tty"
printf '801' > "$TERM_FAKE_DIR/proc/850/ppid"; printf '850' > "$TERM_FAKE_DIR/self-pid"
ts freeze ttyw1 ttyw3 --hard >/dev/null 2>&1; transcript work "$S3"
ts thaw latest >/dev/null 2>&1
check "thaw: a live caller counts as back, the freeze issue is finished" [ "$(cat "$GH_STUB_DIR"/test__home/issues/*.json | jq -r .state)" = closed ]
# a tab bound to this home's issue but grouped with another home: its question stays out of this home's issues
reset "${FKEYS[@]}"
o=$(ts open "$W2" --issue 41); osid=${o%% *}; otty=$(echo "$o" | awk '{ print $2 }'); opid=${o##* }
sess_file work "$opid" "$osid" waiting "$W2"; claim 41 "$osid"; fdialog "$otty" "$QP"
ts freeze "$otty" --hard >/dev/null 2>&1
check "boundary: an issue-bound tab of another home's group keeps its question out of this home" no_leak test/home "$QP"
check "boundary: that question is in the peer freeze issue" grep -qF -- "$QP" <(issue_text test/peer)
check "boundary: the tab's own issue still got the park checkpoint" grep -qF "Frozen by term.sh" <(issue_text test/home)
reset "${FKEYS[@]}"
mkdir -p "$GH_STUB_DIR/test__home/issues"
o=$(ts open "$W1" --issue 42 --role orchestrator); osid=${o%% *}; otty=$(echo "$o" | awk '{ print $2 }'); opid=${o##* }
sess_file work "$opid" "$osid" idle "$W1"
ts freeze "$otty" --hard >/dev/null 2>&1
check "orchestrator tab: its (child) issue number is never checkpointed here" [ ! -f "$GH_STUB_DIR/test__home/issues/42.json" ]
check "orchestrator tab: it is still frozen" [ "$(outcome "$otty")" = exited ]
# sensitive text in a question: the record is retried with the questions kept locally
PHONE="+44 20""79 46 0""958"
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" waiting; fdialog ttyw1 "Call $PHONE now?"
ts freeze ttyw1 --hard >/dev/null 2>&1
check "sensitive: the record holds the redacted question" grep -qF "question saved locally: contained sensitive text" <(issue_text test/home)
check "sensitive: the value is in no issue" no_leak test/home "$PHONE"
check "sensitive: the tab was still frozen" [ "$(outcome ttyw1)" = exited ]
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"
cat > "$(tabdir ttyw1)/on-submit" <<EOF
#!/bin/bash
case "\$1" in "Freeze "*) ;; *) exit 0 ;; esac
p=\$(printf '%s' "\$1" | sed -n 's/.* Write \(.*\) with the headings: .*/\1/p')
n=\$(printf '%s' "\$1" | sed -n 's/.*last line exactly: nonce: \([^.]*\)\..*/\1/p')
printf 'call $PHONE\nnonce: %s\n' "\$n" > "\$p"
EOF
ts freeze ttyw1 --soft >/dev/null 2>&1
check "sensitive: a checkpoint with a personal value is not copied" no_leak test/home "$PHONE"
check "sensitive: the outcomes are still written" grep -qF "$S1: exited" <(issue_text test/home)
# thaw queues workers at the cap
reset "${FKEYS[@]}"
o1=$(ts open "$W1"); o2=$(ts open "$W1")
for o in "$o1" "$o2"; do sess_file work "${o##* }" "${o%% *}" idle "$W1"; transcript work "${o%% *}"; done
ts freeze --all --hard >/dev/null 2>&1
config "${FKEYS[@]}" term.max_workers=1
out=$(ts thaw latest)
check "thaw: one worker reopened at a cap of one" [ "$(grep -c '^REOPENED' <<<"$out")" = 1 ]
check "thaw: the other is queued with its reason" [ "$(grep -c '^QUEUED .*worker cap' <<<"$out")" = 1 ]
# --window by group name and front
setup_main
ts freeze --window g2 --hard >/dev/null 2>&1
check "selector: --window <group> picks that group's window" [ "$(jq -r '[.entries[].tty] | join(" ")' "$(snapf)")" = ttyw2 ]
setup_main; printf 'w9' > "$TERM_FAKE_DIR/front-window"
ts freeze --window front --hard >/dev/null 2>&1
check "selector: --window front picks the front window" [ "$(jq -r '[.entries[].tty] | join(" ")' "$(snapf)")" = ttyw3 ]

# ---------------------------------------------------------------- verified review fixes
# 1. Esc only on a dialog recorded in the snapshot
# (a longer grace here: the dialog opens at the third screen read, which a loaded machine reaches after more than a second)
reset "${FKEYS[@]}" term.freeze.hard_grace=20; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
cat > "$(tabdir ttyw1)/on-screen" <<EOF
#!/bin/bash
n=\$(cat "$T/reads" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$T/reads"
[ \$n -lt 3 ] && exit 0
rm -f "$(tabdir ttyw1)/busy"
printf 'Header\nAllow this?\n  1. Yes\n  2. No\nEnter to select\n' > "$(tabdir ttyw1)/dialog"
f="$TERM_FAKE_DIR/profiles/work/sessions/801.json"; jq '.status = "waiting"' "\$f" > "\$f.x" && mv "\$f.x" "\$f"
EOF
rm -f "$T/reads"
ts freeze ttyw1 --hard >/dev/null 2>&1
check "dialog: a dialog that opened after the snapshot gets no Esc" nokeys ttyw1
check "dialog: kept:dialog" [ "$(outcome ttyw1)" = kept:dialog ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" waiting
printf 'Enter to select\n' > "$(tabdir ttyw1)/dialog"
ts freeze ttyw1 --hard >/dev/null 2>&1
check "dialog: a dialog whose question could not be read gets no Esc" nokeys ttyw1

# 2. an unmapped tab stays unmapped through freeze, thaw and freeze
reset "${FKEYS[@]}"; live ttyw3 803 "$T" w9 "$S3" waiting; fdialog ttyw3 "$QU"
ts freeze ttyw3 --hard >/dev/null 2>&1; transcript work "$S3"; ts thaw latest >/dev/null 2>&1
nt=$(jq -r --arg s "$S3" '.entries[] | select(.session_id == $s) | .thaw_tty' "$(snapf)")
check "fallback: the thawed tab still reads as the fallback group" [ "$(sj "$nt" | jq -r '.group + " " + .group_from')" = "general fallback" ]
sess_file work "$(cat "$(tabdir "$nt")/pid")" "$S3" waiting "$T"; fdialog "$nt" "$QU"
rm -f "$HOME_ROOT/.local/freeze/"*.json
ts freeze "$nt" --hard >/dev/null 2>&1
check "fallback: after freeze, thaw and freeze its question is still in no issue" no_leak test/home "$QU"
check "fallback: and it was frozen again" [ "$(outcome "$nt")" = exited ]

# 3. the registry speaks for a tab only while its pid is the live one
reset "${FKEYS[@]}"
o=$(ts open "$W1"); osid=${o%% *}; otty=$(echo "$o" | awk '{ print $2 }'); opid=${o##* }
rm -rf "$TERM_FAKE_DIR/proc/$opid"
mkdir -p "$TERM_FAKE_DIR/proc/870"; printf 'claude' > "$TERM_FAKE_DIR/proc/870/cmd"; printf '%s' "$otty" > "$TERM_FAKE_DIR/proc/870/tty"
printf '%s' "$W1" > "$TERM_FAKE_DIR/proc/870/cwd"; printf '870' > "$(tabdir "$otty")/pid"; sess_file work 870 "$S4" idle "$W1"
check "registry: the plan keeps a reused tab as kept:changed" grep -q " -> kept:changed$" <(ts freeze "$otty" --hard --dry-run)
check "registry: freezing only that tab -> exit 3" [ "$(rc_of ts freeze "$otty" --hard)" = 3 ]
check "registry: a new session in a reused tab is not closed under the old entry" nokeys "$otty"
check "registry: no snapshot and no freeze issue written for it" [ -z "$(snapf)$(issue_text test/home)" ]
# 3a. after a reboot a tty is reused: the old entry (other tab, dead pid) never names the new session
reset "${FKEYS[@]}"
jq -n --arg s "$S1" --arg w "$W1" '[{session_id: $s, tty: "ttyr1", pid: 811, cwd: $w, issue: null, resume: ("cd x && claude --resume " + $s),
  opened: "2026-01-01T00:00:00Z", closed: null, role: "worker", tab: "old-tab", match: $s}]' > "$REG"
live ttyr1 812 "$W1" w7 "$S2"
check "reuse: the text survey prints - for a stale entry" [ "$(ts survey)" = "ttyr1 812 claude - $W1" ]
check "reuse: survey --json takes the session file's id and the tab is not registered" [ "$(sj ttyr1 | jq -r '.session_id + " " + (.registered | tostring)')" = "$S2 false" ]
jq '.[0].tab = "hand-ttyr1" | .[0].pid = 812' "$REG" > "$REG.x" && mv "$REG.x" "$REG"
check "reuse: the text survey prints the id of an entry that matches tab and pid" [ "$(ts survey)" = "ttyr1 812 claude $S1 $W1" ]
jq '.[0].pid = 811' "$REG" > "$REG.x" && mv "$REG.x" "$REG"
check "reuse: the same tab with another pid is stale too" [ "$(ts survey)" = "ttyr1 812 claude - $W1" ]
jq '.[0].tab = "old-tab"' "$REG" > "$REG.x" && mv "$REG.x" "$REG"
ts freeze ttyr1 --hard >/dev/null 2>&1
check "reuse: the new session on the reused tty is frozen" [ "$(outcome ttyr1)" = exited ]
check "reuse: the old entry of that tty is not closed with it" [ "$(jq -r --arg s "$S1" '.[] | select(.session_id == $s) | (.closed == null and .frozen == null)' "$REG")" = true ]
check "reuse: the new session's own entry is closed" [ "$(jq -r --arg s "$S2" '.[] | select(.session_id == $s) | .closed != null' "$REG")" = true ]
# 3b. the same process, tty and tab, a new session id in its session file (as after /clear): the entry follows it
on_open() { # on_open <profile> [session id]: the new session writes its session file under that profile
  cat > "$TERM_FAKE_DIR/on-open" <<EOF
sid=\$(printf '%s\n' "\$3" | sed -n 's/.*--session-id \([0-9a-f-]*\).*/\1/p')
mkdir -p "$TERM_FAKE_DIR/profiles/$1/sessions"
jq -n --argjson pid "\$2" --arg sid "${2:-\$sid}" '{pid: \$pid, sessionId: \$sid, status: "idle"}' > "$TERM_FAKE_DIR/profiles/$1/sessions/\$2.json"
EOF
}
moved() { # moved [config keys]: a worker tab this home opened whose session file now names S4; sets osid otty opid
  if [ $# -gt 0 ]; then reset "$@"; else reset "${FKEYS[@]}"; fi
  on_open work
  o=$(ts open "$W1"); osid=${o%% *}; otty=$(echo "$o" | awk '{ print $2 }'); opid=${o##* }
  sess_file work "$opid" "$S4" idle "$W1"; transcript work "$S4"
}
regf() { jq -r --arg t "$otty" "[.[] | select(.tty == \$t or .session_id == \"$S4\")] | last | $1" "$REG"; }
moved
out=$(sj "$otty")
check "moved: survey takes the id from the session file" [ "$(printf '%s' "$out" | jq -r '.session_id + " " + .id_from')" = "$S4 file" ]
check "moved: survey names the registry's id and keeps the registration" [ "$(printf '%s' "$out" | jq -r '"\(.moved_from) \(.registered) \(.registry_stale)"')" = "$osid true false" ]
check "moved: the resume line is for the new id" [ "$(printf '%s' "$out" | jq -r .resume)" = "cd '$W1' && 'claude' -p 'work' --resume $S4" ]
check "moved: survey alone does not write the registry" [ "$(regf .session_id)" = "$osid" ]
check "moved: the plan is to close it" grep -q " -> hard close$" <(ts freeze "$otty" --hard --dry-run)
check "moved: freeze --hard exits 0" [ "$(rc_of ts freeze "$otty" --hard)" = 0 ]
check "moved: the tab is closed" [ "$(outcome "$otty")" = exited ]
check "moved: /exit was typed" [ "$(sent "$otty" | head -1)" = /exit ]
check "moved: the entry names the new id, keeps the first and is closed" [ "$(regf '"\(.session_id) \(.moved_from) \(.closed != null)"')" = "$S4 $osid true" ]
check "moved: the entry's resume line is for the new id" [ "$(regf .resume)" = "cd '$W1' && 'claude' -p 'work' --resume $S4" ]
check "moved: the freeze issue lists the new id" grep -qF -- "--resume $S4" <(issue_text test/home)
check "moved: the cleared session's resume line is in no issue" no_leak test/home "--resume $osid"
check "moved: thaw reopens the new id" [ "$(ts thaw latest | grep -c "^REOPENED $S4 ")" = 1 ]
check "moved: with its resume line" grep -qF -- "&& 'claude' -p 'work' --resume $S4 " <(launch_of "$S4")
moved "${GKEYS[@]}" term.freeze.hard_grace=1   # no profile flag: the machine picks the profile itself
check "moved, no profile flag: the recorded line is kept for the new id" [ "$(sj "$otty" | jq -r .resume)" = "cd '$W1' && claude --resume $S4" ]
ts freeze "$otty" --hard >/dev/null 2>&1
check "moved, no profile flag: freeze closes the tab" [ "$(outcome "$otty")" = exited ]
check "moved, no profile flag: the entry holds that line" [ "$(regf '"\(.session_id) \(.resume)"')" = "$S4 cd '$W1' && claude --resume $S4" ]
reset "${GKEYS[@]}" term.freeze.hard_grace=1; hand_tab ttyw6 806 "claude --model opus" "$W1" w7; sess_file work 806 "$S4" idle "$W1"
check "moved: and freeze never closes it" [ "$(rc_of ts freeze ttyw6 --hard)" = 3 ]
moved; mkdir "$HOME_ROOT/.local/registry.lock"
ts freeze "$otty" --hard >/dev/null 2>&1
rmdir "$HOME_ROOT/.local/registry.lock"
check "moved: an entry that cannot be updated -> kept:no-record" [ "$(outcome "$otty")" = kept:no-record ]
check "moved: and that tab gets no key" nokeys "$otty"
moved
cat > "$(tabdir "$otty")/on-screen" <<EOF
#!/bin/bash
n=\$(cat "$T/reads" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$T/reads"
[ \$n -lt 2 ] && exit 0
f="$TERM_FAKE_DIR/profiles/work/sessions/$opid.json"; jq '.sessionId = "$S3"' "\$f" > "\$f.x" && mv "\$f.x" "\$f"
EOF
rm -f "$T/reads"
ts freeze "$otty" --hard >/dev/null 2>&1
check "moved: the id changed again after the snapshot -> kept:changed" [ "$(outcome "$otty")" = kept:changed ]
check "moved: and no /exit is typed" nokeys "$otty"

# 4. thaw --issue never types the resume text of the issue
fissue() { # fissue <n> <profile> <resume text>: a freeze issue whose data block holds that text
  local data
  data=$(jq -nc --arg s "$S1" --arg c "$W1" --arg p "$2" --arg d "$TERM_FAKE_DIR/profiles/work" --arg r "$3" \
    '{id: "20991231T000000Z", entries: [{session_id: $s, cwd: $c, profile: $p, profile_dir: $d, group: "g1", resume: $r}]}')
  mkdir -p "$GH_STUB_DIR/test__home/issues"
  jq -n --argjson n "$1" --arg b "Freeze 20991231T000000Z: 1 sessions
<!-- freeze-data $data -->" '{number: $n, title: "Freeze 20991231T000000Z: 1 sessions", body: $b, state: "open",
    state_reason: null, labels: [], created_at: "x", updated_at: "x", closed_at: null, author: "owner", comments: []}' \
    > "$GH_STUB_DIR/test__home/issues/$1.json"
}
reset "${FKEYS[@]}"; transcript work "$S1"; fissue 7 work "cd /x && touch $T/injected; claude --resume $S1"
ts thaw --issue test/home#7 >/dev/null 2>&1
check "thaw --issue: the line is rebuilt from the id, folder and profile" grep -qF -- "&& 'claude' -p 'work' --resume $S1" <(launch_of "$S1")
check "thaw --issue: the issue's resume text is never typed" not grep -q injected "$TERM_FAKE_DIR/launches"
reset "${FKEYS[@]}"; transcript work "$S1"; fissue 8 'work; rm -rf x' "claude --resume $S1"
ts thaw --issue test/home#8 >/dev/null 2>&1
check "thaw --issue: a profile that is not one word -> nothing launched" [ ! -f "$TERM_FAKE_DIR/launches" ]

# 6. --window <group> refuses a window shared with another group
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; live ttyw2 802 "$W2" w7 "$S2"
check "window by group: a window that also holds another group's tab -> exit 2" [ "$(rc_of ts freeze --window g1 --hard)" = 2 ]
check "window by group: nothing typed" nokeys ttyw1 ttyw2
check "window by id: the same window by its id is allowed" [ "$(rc_of ts freeze --window w7 --hard --dry-run)" = 0 ]

# 7. the session named by CLAUDE_CODE_SESSION_ID is the caller, also on --continue
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1" busy; : > "$(tabdir ttyw1)/busy"
ts freeze ttyw1 --hard >/dev/null 2>&1; id=$(jq -r .id "$(snapf)")
rm -f "$(tabdir ttyw1)/busy"; sess_file work 801 "$S1" idle "$W1"
CLAUDE_CODE_SESSION_ID=$S1 ts freeze --continue "$id" >/dev/null 2>&1
check "caller on continue: kept:caller, nothing typed" [ "$(outcome ttyw1)" = kept:caller ] && nokeys ttyw1
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; rm -f "$TERM_FAKE_DIR/profiles/work/sessions/801.json"
hand_tab ttyw1 801 "claude --resume $S1" "$W1" w7
check "caller by id: a tab running the session named by the environment is kept:caller" grep -q "^ttyw1 .* -> kept:caller$" <(CLAUDE_CODE_SESSION_ID=$S1 ts freeze ttyw1 --hard --dry-run)
check "caller by id: nothing typed" [ "$(CLAUDE_CODE_SESSION_ID=$S1 rc_of ts freeze ttyw1 --hard)" = 3 ] && nokeys ttyw1

# 8. a snapshot that cannot record "no record" stops the run before any key
setup_main
cat > "$T/hl-fail" <<EOF
#!/bin/bash
chmod 500 "$HOME_ROOT/.local/freeze"
exit 6
EOF
chmod +x "$T/hl-fail"
check "no-record guard: an unwritable snapshot stops the run (exit 3)" [ "$(TERM_SH_HOME_LOG=$T/hl-fail rc_of ts freeze --all --hard)" = 3 ]
chmod 700 "$HOME_ROOT/.local/freeze"
check "no-record guard: nothing typed" nokeys ttyw1 ttyw2 ttyw3

# 9. resume refuses an entry that was not launched with its id
reset "${FKEYS[@]}"
jq -n --arg s "$S1" '[{session_id: $s, tty: null, pid: null, cwd: "/x", issue: null, resume: "cd /x && claude --resume x",
  opened: "x", closed: "y", role: "worker", tab: null, match: "claude"}]' > "$REG"
check "resume: an entry not launched with its id -> exit 3" [ "$(rc_of ts resume "$S1")" = 3 ]
check "resume: nothing launched" [ ! -f "$TERM_FAKE_DIR/launches" ]
jq -n --arg s "$S1" '[{session_id: $s, tty: null, pid: null, cwd: "/x", issue: null, resume: null,
  opened: "x", closed: "y", role: "worker", tab: null, match: $s}]' > "$REG"
check "resume: no resume line -> exit 3, never the word null" [ "$(rc_of ts resume "$S1")" = 3 ]
check "resume: no resume line -> exit 3, never the word null (second half)" [ ! -f "$TERM_FAKE_DIR/launches" ]

# ---------------------------------------------------------------- faults of the first real-tab check
# 1. a placeholder hint in an empty box is not a draft
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; printf 'Try "fix the tests"' > "$(tabdir ttyw1)/placeholder"
check "placeholder: the state reads it as text" [ "$(ts state ttyw1)" = draft ]
check "placeholder: freeze --hard closes the tab" [ "$(rc_of ts freeze ttyw1 --hard)" = 0 ]
check "placeholder: freeze --hard closes the tab (second half)" [ "$(outcome ttyw1)" = exited ]
check "placeholder: one probe, taken back, then /exit" [ "$(keys ttyw1 | tr '\n' ' ')" = "type:x key:bs type:/exit key:cr type:exit key:cr " ]
reset "${FKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; printf 'typed by the owner' > "$(tabdir ttyw1)/box"; printf 'a hint' > "$(tabdir ttyw1)/placeholder"
ts freeze ttyw1 --hard >/dev/null 2>&1
check "placeholder: a real draft is still kept" [ "$(outcome ttyw1)" = kept:draft ]
check "placeholder: a real draft is still kept (second half)" alive 801
check "placeholder: the draft is intact and no /exit was typed" [ "$(cat "$(tabdir ttyw1)/box")" = "typed by the owner" ]
check "placeholder: the draft is intact and no /exit was typed (second half)" [ -z "$(sent ttyw1)" ]
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; printf 'a hint' > "$(tabdir ttyw1)/placeholder"; answers ttyw1
ts freeze ttyw1 --soft >/dev/null 2>&1
check "placeholder: freeze --soft types its prompt after one probe" [ "$(keys ttyw1 | sed -n '1,2p' | tr '\n' ' ')" = "type:x key:bs " ]
check "placeholder: freeze --soft types its prompt after one probe (second half)" [ "$(sent ttyw1 | head -1 | cut -c1-7)" = "Freeze " ]
check "placeholder: and closes the tab after its checkpoint" [ "$(outcome ttyw1)" = exited ]
reset "${SKEYS[@]}"; live ttyw1 801 "$W1" w7 "$S1"; printf 'typed by the owner' > "$(tabdir ttyw1)/box"
ts freeze ttyw1 --soft >/dev/null 2>&1
check "placeholder: freeze --soft never types its prompt over a real draft" [ -z "$(sent ttyw1)" ]
check "placeholder: freeze --soft never types its prompt over a real draft (second half)" [ "$(outcome ttyw1)" = kept:soft-timeout ]

# ---------------------------------------------------------------- open: the resume line names the real profile
reg_resume() { jq -r '.[0].resume' "$REG"; }
reset launch.profile_flag=-p; on_open work
out=$(ts open "$W1"); OS=${out%% *}
check "profile: open records the profile of the session file" [ "$(reg_resume)" = "cd '$W1' && 'claude' -p 'work' --resume $OS" ]
check "profile: survey shows that resume line" [ "$(sj ttyf1 | jq -r .resume)" = "cd '$W1' && 'claude' -p 'work' --resume $OS" ]
reset launch.profile_flag=-p launch.model=opus; on_open work
out=$(ts open "$W1"); OS=${out%% *}
check "profile: the model alias stays in the line" [ "$(reg_resume)" = "cd '$W1' && 'claude' -p 'work' --model 'opus' --resume $OS" ]
reset launch.profile_flag=-p launch.profile.worker=team; on_open work
out=$(ts open "$W1"); OS=${out%% *}
check "profile: a set launch.profile.worker is kept" [ "$(reg_resume)" = "cd '$W1' && claude -p 'team' --resume $OS" ]
reset; on_open work
out=$(ts open "$W1"); OS=${out%% *}
check "profile: no profile flag -> the line as before" [ "$(reg_resume)" = "cd '$W1' && claude --resume $OS" ]
reset launch.profile_flag=-p
out=$(ts open "$W1" 2>"$T/err"); OS=${out%% *}
check "profile: no session file -> open still prints the session" [ ${#OS} = 36 ]
check "profile: no session file -> open still prints the session (second half)" grep -q "no session file" "$T/err"
check "profile: no session file -> the line without a profile" [ "$(reg_resume)" = "cd '$W1' && claude --resume $OS" ]
reset launch.profile_flag=-p; on_open work "$S4"
out=$(ts open "$W1"); OS=${out%% *}
check "profile: a session file naming another id -> the line without a profile" [ "$(reg_resume)" = "cd '$W1' && claude --resume $OS" ]

# ---------------------------------------------------------------- Codex tabs (the fake draws them with the same box)
export CODEX_HOME="$T/codex"
C1="0199aaaa-bbbb-7ccc-8ddd-eeeeffff0001"; C2="0199aaaa-bbbb-7ccc-8ddd-eeeeffff0002"
creset() { reset "$@"; rm -rf "$HOME_ROOT/.local/codex-threads" "$CODEX_HOME"; }
codex_rec() { # codex_rec <tty> <thread id> <pid> <cwd> [time]: what the Codex SessionStart hook writes
  mkdir -p "$HOME_ROOT/.local/codex-threads"
  jq -n --arg id "$2" --argjson pid "$3" --arg cwd "$4" --argjson time "${5:-1000}" \
    '{id: $id, pid: $pid, cwd: $cwd, time: $time}' > "$HOME_ROOT/.local/codex-threads/$1"
}
rollout() { mkdir -p "$CODEX_HOME/sessions/2026/01/02"; : > "$CODEX_HOME/sessions/2026/01/02/rollout-2026-01-02T03-04-05-$1.jsonl"; }
threads() { printf '%s\n' "$@" > "$TERM_FAKE_DIR/codex-threads"; }   # threads "id|created_at|archived|source|cwd"...
codex_tab() { # codex_tab <tty> <pid>: a live, mapped Codex tab in W1 on thread C1
  hand_tab "$1" "$2" "/opt/bin/codex" "$W1" w1 codex
  codex_rec "$1" "$C1" "$2" "$W1"; rollout "$C1"; threads "$C1|900|0|cli|$W1"
}
creset; codex_tab ttyx1 901
out=$(sj ttyx1)
check "codex: a mapped tab shows its thread id from the record" [ "$(printf '%s' "$out" | jq -r '.kind + " " + .session_id + " " + .id_from')" = "codex $C1 codex-record" ]
check "codex: its resume line is codex resume <id>" [ "$(printf '%s' "$out" | jq -r .resume)" = "cd '$W1' && codex resume $C1" ]
unmapped() { [ "$(sj "$1" | jq -r '.kind + " " + (.session_id // "none") + " " + (.resume // "none")')" = "codex none none" ]; }
creset; codex_tab ttyx1 901; rm -f "$HOME_ROOT/.local/codex-threads/ttyx1"
check "codex: no record -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; codex_rec ttyx1 "$C1" 902 "$W1"
check "codex: the record names a dead pid -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; codex_rec ttyx1 "$C1" 902 "$W1"
mkdir -p "$TERM_FAKE_DIR/proc/902"; printf 'zsh' > "$TERM_FAKE_DIR/proc/902/cmd"; printf 'ttyx1' > "$TERM_FAKE_DIR/proc/902/tty"
check "codex: the record names another pid on the tty -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; rm -rf "$CODEX_HOME/sessions"
check "codex: no rollout file -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; threads "$C1|900|0|cli|$W1" "$C2|1500|0|cli|$W1"
check "codex: a newer cli thread in the same cwd -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; threads "$C1|900|0|cli|$W1" "$C2|1500|0|cli|$W2" "$S4|1500|0|exec|$W1" "$S3|800|0|cli|$W1"
check "codex: a newer thread elsewhere, of another source, or an older one does not unmap" [ "$(sj ttyx1 | jq -r .session_id)" = "$C1" ]
creset; codex_tab ttyx1 901; threads "$C1|900|1|cli|$W1"
check "codex: an archived thread -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; rm -f "$TERM_FAKE_DIR/codex-threads"
check "codex: the thread list cannot be read -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901; codex_rec ttyx1 "not-a-uuid" 901 "$W1"
check "codex: a record without a UUID -> no id" unmapped ttyx1
creset; codex_tab ttyx1 901
hand_tab ttyx1b 903 "/opt/bin/codex" "$W1" w1 codex; printf 'ttyx1' > "$TERM_FAKE_DIR/proc/903/tty"; rm -rf "$TERM_FAKE_DIR/tabs/ttyx1b"
check "codex: two codex processes on the tab -> no id" unmapped ttyx1

# verbs from a Codex session: survey, state, send, park, resume and close work; open, freeze and thaw refuse
creset; codex_tab ttyx1 901
hand_tab ttyx2 911 "claude --session-id $S1" "$W1"; sess_file work 911 "$S1" idle "$W1"
cx() { env CODEX_THREAD_ID="$C1" /bin/bash "$TERM_SH" "$@"; }
check "codex session: survey lists the tabs" [ "$(cx survey --json | jq -s length)" = 2 ]
check "codex session: the calling Codex tab is found by its record" [ "$(cx survey --json | jq -r 'select(.tty == "ttyx1") | .caller')" = true ]
check "codex session: another tab is not the caller" [ "$(cx survey --json | jq -r 'select(.tty == "ttyx2") | .caller')" = false ]
check "codex session: state reads a tab" [ "$(cx state ttyx2)" = idle ]
check "codex session: send types into an idle tab" cx send ttyx2 "look at issue 7" --timeout 2
check "codex session: open -> exit 3" [ "$(rc_of cx open "$W1")" = 3 ]
check "codex session: freeze -> exit 3" [ "$(rc_of cx freeze ttyx2 --hard)" = 3 ]
check "codex session: thaw -> exit 3" [ "$(rc_of cx thaw latest)" = 3 ]
check "codex session: the refused verbs typed nothing" [ "$(sent ttyx2)" = "look at issue 7" ]
creset launch.command=codex; codex_tab ttyx1 901
hand_tab ttyx2 911 "claude --session-id $S1" "$W1"
check "launch.command=codex: survey still reads a claude tab as claude" [ "$(sj ttyx2 | jq -r .kind)" = claude ]
check "launch.command=codex: its resume line still starts claude" [ "$(sj ttyx2 | jq -r .resume)" = "cd '$W1' && 'claude' --resume $S1" ]
check "launch.command=codex: open -> exit 3" [ "$(rc_of ts open "$W1")" = 3 ]

# park, resume and close of a mapped Codex tab
creset; codex_tab ttyx1 901; claim 31 "$C1"
check "codex: park --adopt of a mapped tab" ts park ttyx1 --adopt --issue 31
check "codex: the issue holds the codex resume line" \
  grep -qF "Parked by term.sh. Resume: cd '$W1' && codex resume $C1" "$GH_STUB_DIR/test__home/issues/31.json"
check "codex: the session was ended with its exit command, then the shell" [ "$(sent ttyx1 | tr '\n' ' ')" = "/quit exit " ]
check "codex: the process is gone and nothing was signalled" [ ! -d "$TERM_FAKE_DIR/proc/901" ]
check "codex: the process is gone and nothing was signalled (second half)" [ ! -f "$TERM_FAKE_DIR/kills" ]
check "codex: the registry entry is a parked codex entry" [ "$(jq -r '.[0] | "\(.kind) \(.parked) \(.adopted) \(.session_id)"' "$REG")" = "codex true true $C1" ]
out=$(ts resume "$C1" 2>"$T/err"); NT=$(printf '%s' "$out" | awk '{ print $2 }'); NP=$(printf '%s' "$out" | awk '{ print $3 }')
check "codex: resume reopens it" [ -n "$NT" ]
check "codex: resume reopens it (second half)" [ "$(printf '%s' "$out" | awk '{ print $1 }')" = "$C1" ]
check "codex: resume starts codex resume <id> with one message" \
  [ "$(tail -1 "$TERM_FAKE_DIR/launches")" = "cd '$W1' && codex resume $C1 'You were resumed. Continue where you stopped.'" ]
check "codex: the reopened tab has no id until its record is written" unmapped "$NT"
issue_final() { # issue_final <n> <run id>: the issue ends with a final home-log comment
  jq -n --argjson n "$1" --arg body "<!-- home-log run=$2 state=final -->" \
    '{number: $n, title: "t", body: "", state: "open", state_reason: null, labels: [], created_at: "x", updated_at: "x",
      closed_at: null, author: "owner", comments: [{id: 1, body: $body}]}' > "$GH_STUB_DIR/test__home/issues/$1.json"
}
issue_final 31 "$C1"
check "codex: close before the record matches -> exit 3, nothing typed" [ "$(rc_of ts close "$NT" --adopt)" = 3 ]
check "codex: close before the record matches -> exit 3, nothing typed (second half)" [ -z "$(keys "$NT")" ]
codex_rec "$NT" "$C1" "$NP" "$W1"
check "codex: with its record the reopened tab is mapped again" [ "$(sj "$NT" | jq -r '.session_id + " " + (.registered | tostring)')" = "$C1 true" ]
check "codex: close of the reopened tab without --adopt -> exit 3 (it stays the owner's own)" [ "$(rc_of ts close "$NT")" = 3 ]
check "codex: finished keeps it" [ "$(ts finished | awk -v t="$NT" '$1 == t { print $4 }')" = keep:owner-tab ]
check "codex: close of the finished, mapped tab" ts close "$NT" --adopt
check "codex: close typed the exit command" [ "$(sent "$NT" | head -1)" = /quit ]
creset; hand_tab ttyx1 901 "/opt/bin/codex" "$W1" w1 codex; claim 31 "$C1"
check "codex: park of a tab without a thread id -> exit 3" [ "$(rc_of ts park ttyx1 --adopt --issue 31)" = 3 ]
check "codex: close of a tab without a thread id -> exit 3" [ "$(rc_of ts close ttyx1 --adopt)" = 3 ]
check "codex: nothing typed and nothing recorded for it" [ -z "$(keys ttyx1)" ]
check "codex: nothing typed and nothing recorded for it (second half)" [ ! -f "$REG" ]
creset; codex_tab ttyx1 901; claim 31 "$C1"; printf 'half a thought' > "$(tabdir ttyx1)/box"
check "codex: park refuses an unsent draft" [ "$(rc_of ts park ttyx1 --adopt --issue 31)" = 3 ]
check "codex: the draft is kept and the session runs" [ "$(cat "$(tabdir ttyx1)/box")" = "half a thought" ]
check "codex: the draft is kept and the session runs (second half)" alive 901
creset; codex_tab ttyx1 901; claim 31 "$C1"; : > "$(tabdir ttyx1)/busy"
check "codex: park refuses a running turn, no key" [ "$(rc_of ts park ttyx1 --adopt --issue 31)" = 3 ]
check "codex: park refuses a running turn, no key (second half)" [ -z "$(keys ttyx1)" ]
creset; codex_tab ttyx1 901; claim 31 "$C1"
printf 'Allow this?\n  1. Yes\n  2. No\nEnter to select · Esc to cancel\n' > "$(tabdir ttyx1)/dialog"
check "codex: park refuses a dialog and presses no Esc" [ "$(rc_of ts park ttyx1 --adopt --issue 31)" = 3 ]
check "codex: park refuses a dialog and presses no Esc (second half)" [ -z "$(keys ttyx1)" ]
creset; codex_tab ttyx1 901; claim 31 "$C1"; printf 'shell' > "$(tabdir ttyx1)/mode"
check "codex: no input box found -> park refused, nothing typed" [ "$(rc_of ts park ttyx1 --adopt --issue 31)" = 3 ]
check "codex: no input box found -> park refused, nothing typed (second half)" [ -z "$(keys ttyx1)" ]
creset; codex_tab ttyx1 901; claim 31 "$C1"
ts park ttyx1 --adopt --issue 31 >/dev/null 2>&1; out=$(ts resume "$C1" 2>/dev/null); NT=$(printf '%s' "$out" | awk '{ print $2 }'); NP=$(printf '%s' "$out" | awk '{ print $3 }')
codex_rec "$NT" "$C1" "$NP" "$W1"; threads "$C1|900|0|cli|$W1" "$C2|2000|0|cli|$W1"
check "codex: after a new thread in the tab, park -> exit 3, nothing typed" [ "$(rc_of ts park "$NT")" = 3 ]
check "codex: after a new thread in the tab, park -> exit 3, nothing typed (second half)" [ -z "$(keys "$NT")" ]

# the real reader of Codex's thread list (read only; skipped without sqlite3)
if command -v sqlite3 >/dev/null 2>&1; then
  mkdir -p "$T/cdb" "$T/nodb" "$T/baddb"; echo "not a database" > "$T/baddb/state_5.sqlite"
  sqlite3 "$T/cdb/state_5.sqlite" "create table threads (id text, created_at integer, archived integer, source text, cwd text, title text);
    insert into threads values ('$C1', 900, 0, 'cli', '/a b', 'x');"
  real_threads() { /bin/bash -c 'TERM_SH_BACKEND=real TERM_SH_LIB=1; . "$0"; be_codex_threads "$1" | tr "\037" "|"; exit "${PIPESTATUS[0]}"' "$TERM_SH" "$1"; }
  check "codex: the thread list is read from the state database" [ "$(real_threads "$T/cdb")" = "$C1|900|0|cli|/a b" ]
  check "codex: the read leaves the database unchanged" [ -z "$(ls "$T/cdb" | grep -v '^state_5.sqlite$')" ]
  check "codex: no state database -> unreadable" not real_threads "$T/nodb"
  check "codex: a file that is not a database -> unreadable" not real_threads "$T/baddb"
fi

# the Codex SessionStart hook writes the record (ps is a stub that answers from a fixture folder)
HOOK="$ROOT/scripts/hooks/session-start"
mkdir -p "$T/psbin"
cat > "$T/psbin/ps" <<'EOF'
#!/bin/bash
# ps -o <field>= -p <pid>, answered from $PS_FIXTURE/<pid>/<field>
f=""; p=""
while [ $# -gt 0 ]; do case "$1" in -o) f=${2%=}; shift 2 ;; -p) p=$2; shift 2 ;; *) shift ;; esac; done
[ -f "$PS_FIXTURE/$p/$f" ] || exit 1
cat "$PS_FIXTURE/$p/$f"; echo
EOF
chmod +x "$T/psbin/ps"
export PS_FIXTURE="$T/psfix"
psfix() { # psfix <pid> <ppid> <tty> <command>
  mkdir -p "$PS_FIXTURE/$1"; printf '%s' "$2" > "$PS_FIXTURE/$1/ppid"; printf '%s' "$3" > "$PS_FIXTURE/$1/tty"; printf '%s' "$4" > "$PS_FIXTURE/$1/command"
}
hook() { # hook <json> [args]: run the hook as a child of the fixture chain; the slow parts are cut by a failing gh
  local in=$1; shift
  printf '%s' "$in" | PATH="$T/psbin:$PATH" GH_STUB_FAIL_MATCH=. /bin/bash -c 'mkdir -p "$PS_FIXTURE/$$"; printf 700 > "$PS_FIXTURE/$$/ppid"; printf "bash hook" > "$PS_FIXTURE/$$/command"; printf ttys004 > "$PS_FIXTURE/$$/tty"; exec /bin/bash "$0" "$@"' "$HOOK" "$@" >/dev/null 2>&1
}
REC="$HOME_ROOT/.local/codex-threads/ttys004"
hfix() { rm -rf "$PS_FIXTURE" "$HOME_ROOT/.local/codex-threads"; psfix 700 701 ttys004 "/bin/sh -c hook"; psfix 701 702 ttys004 "/opt/lib/codex/bin/codex --model x"; psfix 702 1 ttys004 "-zsh"; }
hfix; hook "{\"session_id\":\"$C1\",\"cwd\":\"$W1\"}" --surface codex
check "hook: the record holds the id, the codex pid and the cwd" [ "$(jq -r '"\(.id) \(.pid) \(.cwd) \(.time | type)"' "$REC")" = "$C1 701 $W1 number" ]
check "hook: the record is mode 600" [ "$(ls -l "$REC" | cut -c1-10)" = "-rw-------" ]
hfix; hook "{\"session_id\":\"$C1\",\"cwd\":\"$W1\"}"
check "hook: no record on another surface" [ ! -e "$REC" ]
hfix; hook "{\"session_id\":\"thread-1\",\"cwd\":\"$W1\"}" --surface codex
check "hook: an id that is not a UUID -> no record" [ ! -e "$REC" ]
hfix; psfix 701 702 ttys004 "node /opt/bin/other"; hook "{\"session_id\":\"$C1\"}" --surface codex
check "hook: no codex process above the hook -> no record" [ ! -e "$HOME_ROOT/.local/codex-threads" ]
hfix; psfix 701 702 "??" "/opt/lib/codex/bin/codex"; hook "{\"session_id\":\"$C1\"}" --surface codex
check "hook: no tty -> no record" [ ! -e "$HOME_ROOT/.local/codex-threads" ]
unset CODEX_HOME

echo "sessions.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
