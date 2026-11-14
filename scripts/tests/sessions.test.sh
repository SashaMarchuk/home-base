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
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT

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
check "caller: no signal -> no caller" [ "$(ts survey --json | jq -s '[.[] | select(.caller)] | length')" = 0 ]
check "caller: an id with no session file -> no caller" [ "$(CLAUDE_CODE_SESSION_ID=$S4 ts survey --json | jq -s '[.[] | select(.caller)] | length')" = 0 ]

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
check "groups: survey reads the recorded group" [ "$(sj "$t" | jq -r '.group + " " + .group_from')" = "g2 registry" ]
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
check "freeze: --all --hard exits 0" [ "$(rc_of ts freeze --all --hard)" = 0 ]
check "freeze: the idle g1 tab exited" [ "$(outcome ttyw1)" = exited ]
check "freeze: the dialog tabs exited after one Esc each" [ "$(outcome ttyw2) $(outcome ttyw3)" = "exited exited" ]
check "freeze: one Esc on each dialog" [ "$(keys ttyw2 | grep -c key:esc) $(keys ttyw3 | grep -c key:esc)" = "1 1" ]
check "freeze: no dialog answered" [ ! -f "$(tabdir ttyw2)/answered" ] && [ ! -f "$(tabdir ttyw3)/answered" ]
check "freeze: /exit typed into the closed tabs" [ "$(sent ttyw1 | head -1)" = /exit ]
check "freeze: their processes are gone" not alive 801
check "freeze: codex and shell tabs listed, not touched" [ "$(outcome ttyw4) $(outcome ttyw5)" = "kept:not-claude kept:not-claude" ]
check "freeze: no key in the codex or shell tab" nokeys ttyw4 ttyw5
check "freeze: nothing signalled" [ ! -f "$TERM_FAKE_DIR/kills" ]
check "freeze: the snapshot keeps the dialog question and options" \
  [ "$(jq -r --arg t ttyw3 '.entries[] | select(.tty == $t) | .question + " | " + (.options | join(","))' "$(snapf)")" = "Header $QU | 1. Yes,2. No" ]
check "freeze: one freeze issue in this home" [ "$(ls "$GH_STUB_DIR/test__home/issues" | wc -l | tr -d ' ')" = 1 ]
check "freeze: one freeze issue in the peer home" [ "$(ls "$GH_STUB_DIR/test__peer/issues" | wc -l | tr -d ' ')" = 1 ]
check "freeze: this home's issue lists the g1 session with its resume line" issue_text test/home | grep -qF "-p 'work' --model 'opus' --resume $S1"
check "freeze: the freeze issues are parked" [ "$(cat "$GH_STUB_DIR"/test__*/issues/*.json | jq -r '.labels | index("status:parked") != null' | sort -u)" = true ]
check "freeze: the peer question is in the peer home's issue" issue_text test/peer | grep -qF "$QP"
check "boundary: the peer question never enters this home's issue" no_leak test/home "$QP"
check "boundary: an unmapped tab's question never enters this home's issue" no_leak test/home "$QU"
check "boundary: an unmapped tab's folder never enters this home's issue" not grep -qF "name-ttyw3" <(issue_text test/home)
check "boundary: the unmapped tab is a pointer line" issue_text test/home | grep -qF "$S3: unmapped tab"
cp -R "$GH_STUB_DIR/test__home" "$GH_STUB_DIR/test__leak"
f=$(ls "$GH_STUB_DIR/test__leak/issues/"*.json | head -1)
jq --arg q "$QU" '.comments += [{id: 99, body: ("open question: " + $q)}]' "$f" > "$f.x" && mv "$f.x" "$f"
check "boundary: the check fails when an unmapped question is in this home's issue" not no_leak test/leak "$QU"
check "freeze: adopted tabs recorded, closed and frozen" [ "$(jq -r '[.[] | select(.adopted and .closed != null and .frozen != null)] | length' "$REG")" = 3 ]
check "freeze: the lock is released" [ ! -d "$HOME_ROOT/.local/freeze.lock" ]
check "freeze: every file under this home's .local" [ -z "$(find "$T" -newer "$HOME_ROOT/home.config" -type f -path '*freeze*' ! -path "$HOME_ROOT/.local/*")" ]

# snapshot and record before the first key
setup_main
printf '#!/bin/bash\n[ -n "$(ls %s/*.json 2>/dev/null)" ] && [ -n "$(ls %s 2>/dev/null)" ] && echo before >> %s\n' \
  "$HOME_ROOT/.local/freeze" "$GH_STUB_DIR/test__home/issues" "$T/order" > "$(tabdir ttyw1)/on-submit"
ts freeze --all --hard >/dev/null 2>&1
check "snapshot first: snapshot and issue exist when /exit is typed" [ "$(head -1 "$T/order" 2>/dev/null)" = before ]
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
check "caller: its row and resume line are in the issue" issue_text test/home | grep -qF "caller (left open)"
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
check "dialog: one Esc only, no option" [ "$(keys ttyw1 | tr '\n' ' ')" = "key:esc " ] && [ ! -f "$(tabdir ttyw1)/answered" ]
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
check "dry run: writes nothing" [ -z "$(snapf)" ] && [ ! -d "$GH_STUB_DIR/test__home" ]

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
check "linger: kept:linger, nothing signalled" [ "$(outcome ttyw1)" = kept:linger ] && [ ! -f "$TERM_FAKE_DIR/kills" ]

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

echo "sessions.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
