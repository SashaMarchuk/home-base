#!/bin/bash
# Tests for scripts/term/term.sh against the fake backend (no real tab is touched).
# Every rule (openspec/specs/terminal-helpers in the base) has a fixture that must pass and one that must fail.
# Exit 0 when all pass.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
TERM_SH="$ROOT/scripts/term/term.sh"
FAKE="$ROOT/scripts/tests/stubs/term-fake"
mkdir -p "$ROOT/.local"
T=$(mktemp -d "$ROOT/.local/term-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

export HOME_ROOT="$T/home"
export TERM_SH_BACKEND=fake TERM_FAKE_DIR="$T/fake"
export TERM_SH_POLL=0.05 TERM_SH_SETTLE=0 TERM_SH_OPEN_WAIT=1 TERM_SH_EXIT_WAIT=1 TERM_SH_LOCK_TIMEOUT=1
export TERM_SH_HOME_LOG="$T/home-log"
export PATH="$ROOT/scripts/tests/stubs:$PATH" GH_STUB_DIR="$T/ghstore"
unset CODEX_THREAD_ID   # the helpers refuse inside a Codex session; the tests set it where they mean it
unset GH_CONFIG_DIR CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR
mkdir -p "$T/bin"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/cli-whoami"; chmod +x "$T/bin/cli-whoami"
export PATH="$T/bin:$PATH"   # cli-whoami: a stand-in for a CLI identity call that passes
REG="$HOME_ROOT/.local/registry.json"
mkdir -p "$HOME_ROOT/.local" "$T/work dir"
WORK="$T/work dir"
printf '%s\n' repo=test/home labels.needs_owner=needs-test > "$HOME_ROOT/home.config"

cat > "$TERM_SH_HOME_LOG" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$T/home-log.calls"
[ -f "$T/home-log.fail" ] && exit 6
exit 0
EOF
chmod +x "$TERM_SH_HOME_LOG"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $*" >&2; }
check() { local name=$1; shift; if "$@" >>"$T/check.log" 2>&1; then ok; else bad "$name"; fi; }
not() { ! "$@"; }
has_key() { keys | grep -qx -- "$1"; }
out_has() { printf "%s\n" "$out" | grep -qxF -- "$1"; }

ts() { /bin/bash "$TERM_SH" "$@"; }
rc_of() { "$@" >"$T/out" 2>"$T/err"; echo $?; }

config() { # config <lines...>: write .local/config
  printf '%s\n' terminal_helpers=on term.max_workers=4 "term.sessions_dirs=$TERM_FAKE_DIR/profiles/*/sessions" "$@" > "$HOME_ROOT/.local/config"
}
reset() { rm -rf "$TERM_FAKE_DIR" "$REG" "$T/home-log.calls" "$T/home-log.fail" "$GH_STUB_DIR"; mkdir -p "$TERM_FAKE_DIR" "$GH_STUB_DIR"; config "$@"; }
issue() { # issue <n> <last marker state|-> [label...] [--repo O/R]: write one issue into the gh stub
  # The comment is of the run ISSUE_RUN, else of the session new_tab opened last (a worker's run id is its session id).
  local n=$1 st=$2 repo=test/home labels="[]" body; shift 2
  if [ "${1:-}" = --repo ]; then repo=$2; shift 2; fi
  [ $# -gt 0 ] && labels=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
  body="<!-- home-log run=${ISSUE_RUN:-${SID:-run-$n}} state=$st -->"
  mkdir -p "$GH_STUB_DIR/${repo%%/*}__${repo#*/}/issues"
  jq -n --argjson n "$n" --arg st "$st" --arg body "$body" --argjson labels "$labels" \
    '{number: $n, title: "t", body: "", state: "open", state_reason: null, labels: $labels, created_at: "x", updated_at: "x",
      closed_at: null, author: "owner",
      comments: ([{id: 1, body: "a note from a person", author: "owner"}] + (if $st == "-" then [] else [{id: 2, body: $body}] end))}' \
    > "$GH_STUB_DIR/${repo%%/*}__${repo#*/}/issues/$n.json"
}
tabdir() { echo "$TERM_FAKE_DIR/tabs/$1"; }
new_tab() { # new_tab [open args] -> sets SID TTY PID
  local out
  out=$(ts open "$WORK" "$@") || { bad "open failed: $(cat "$T/err" 2>/dev/null)"; return 1; }
  SID=${out%% *}; out=${out#* }; TTY=${out%% *}; PID=${out#* }
}
keys() { cat "$(tabdir "$TTY")/keys" 2>/dev/null; }
sent() { cat "$(tabdir "$TTY")/sent" 2>/dev/null; }
put() { printf '%s' "$2" > "$(tabdir "$TTY")/$1"; }
alive() { [ -d "$TERM_FAKE_DIR/proc/$1" ]; }
mode() { cat "$(tabdir "$TTY")/mode"; }
dialog() { # dialog <with free-text row 0|1> [question]
  {
    echo "Header"
    echo "${2:-Is the login done now?}"
    echo "  1. Yes"
    echo "  2. Not yet"
    [ "$1" = 1 ] && echo "  3. Type something."
    echo "Enter to select · Esc to cancel"
  } > "$(tabdir "$TTY")/dialog"
}

# Static checks shared by rules 2 and 13 ------------------------------------------
# They run over every terminal script, the fake backend and every test file.
TMPWORD="tm""p"; USERS="Use""rs"; SCRATCH="scratch""pad"; PRIV="priv""ate"
lint_paths() { ! grep -nE "/$TMPWORD/|/$USERS/|$SCRATCH|/$PRIV/" "$1" >/dev/null; }
lint_underscore() { ! grep -nE '^[[:space:]]*(function[[:space:]]+)?_[A-Za-z0-9_]*[[:space:]]*\(\)' "$1" >/dev/null; }

# ---------------------------------------------------------------- rule 0: a new tab starts with its command
reset; printf 'ttyowner' > "$TERM_FAKE_DIR/front-tab"; new_tab
check "r0 open types nothing into the new tab" [ -z "$(keys)" ]
check "r0 the tab's command is the login-shell wrapper" grep -Eq "^/[A-Za-z0-9_./-]+ -lic 'eval .*; exec /[A-Za-z0-9_./-]+ -l'$" "$TERM_FAKE_DIR/commands"
check "r0 the command holds no character of the launch line" not grep -q -e "$SID" -e session-id -e "work dir" "$TERM_FAKE_DIR/commands"
check "r0 the shell decodes the launch line" [ "$(cat "$TERM_FAKE_DIR/launches")" = "cd '$WORK' && claude --session-id $SID" ]
check "r0 the focus is given back to the tab that had it" [ "$(cat "$TERM_FAKE_DIR/focus")" = "ttyowner -> $TTY -> ttyowner" ]
check "r0 the focus is given back to the tab that had it (second half)" [ "$(cat "$TERM_FAKE_DIR/front-tab")" = ttyowner ]
check "r0 the recorded process is the session, not the shell around it" [ "$(cat "$TERM_FAKE_DIR/proc/$PID/cmd")" = "claude --session-id $SID" ]
QDIR="$T/it's a \"dir\""; mkdir -p "$QDIR"
BRIEF="say 'hi' to \"them\" for \$5 \\ back\`tick"
reset; out=$(ts open "$QDIR" --brief "$BRIEF"); SID=${out%% *}
got=$(claude() { pwd -P; printf '%s\n' "$@"; }; eval "$(cat "$TERM_FAKE_DIR/launches")")   # run the line as the tab's shell would
check "r0 quotes: the session starts in that folder with the brief as one argument" [ "$got" = "$(cd "$QDIR" && pwd -P)
--session-id
$SID
$BRIEF" ]
check "r0 quotes: none of them is in the tab's command" not grep -q -e '"them"' -e "hi" -e 'tick' "$TERM_FAKE_DIR/commands"
raw_open() { /bin/bash -c 'TERM_SH_LIB=1; . "$0"; be_open "$1" current' "$TERM_SH" "$1"; }
reset
check "r0 a command of another shape (the line in quotes) opens nothing" not raw_open "/bin/zsh -lic 'cd '\\''$QDIR'\\'' && claude'"
check "r0 a bare launch line opens nothing" not raw_open "cd '$WORK' && claude"
check "r0 no tab for either" sh -c '[ -z "$(ls "$1/tabs" 2>/dev/null)" ]' _ "$TERM_FAKE_DIR"
reset; : > "$TERM_FAKE_DIR/open-fail"
check "r0 the tab cannot be created -> exit 4" [ "$(rc_of ts open "$WORK")" = 4 ]
check "r0 failed create: the entry is closed and nothing was typed" [ "$(jq -r '.[0].closed != null' "$REG")" = true ]
check "r0 failed create: the entry is closed and nothing was typed (second half)" [ -z "$(ls "$TERM_FAKE_DIR/tabs" 2>/dev/null)" ]
reset; : > "$TERM_FAKE_DIR/wrapper-holds-line"; new_tab
check "r0 a shell with a higher pid that holds the session id is not recorded" [ "$PID" = 60001 ]
check "r0 a shell with a higher pid that holds the session id is not recorded (second half)" [ "$(jq -r '.[0].pid' "$REG")" = 60001 ]
reset; : > "$TERM_FAKE_DIR/wrapper-holds-line"; : > "$TERM_FAKE_DIR/no-agent"
check "r0 only the shell started -> exit 5, never recorded as the session" [ "$(rc_of ts open "$WORK")" = 5 ]
check "r0 that entry is closed with no pid" [ "$(jq -r '.[0] | (.closed != null and .pid == null)' "$REG")" = true ]
mkdir -p "$T/badod"; printf '#!/bin/bash\nexit 1\n' > "$T/badod/od"; chmod +x "$T/badod/od"
reset
check "r0 the launch line cannot be encoded -> exit 3" [ "$(rc_of env PATH="$T/badod:$PATH" /bin/bash "$TERM_SH" open "$WORK")" = 3 ]
check "r0 nothing opened without the encoding" [ ! -f "$TERM_FAKE_DIR/commands" ]
check "r0 nothing opened without the encoding (second half)" [ "$(jq -r '.[0].closed != null' "$REG")" = true ]
reset; new_tab --issue 21; ts park "$TTY" >/dev/null 2>&1; out=$(ts resume "$SID" 2>/dev/null); TTY=$(echo "$out" | awk '{ print $2 }')
check "r0 resume starts its tab with a command too" [ "$(grep -c -- "-lic 'eval " "$TERM_FAKE_DIR/commands")" = 2 ]
check "r0 resume starts its tab with a command too (second half)" [ -z "$(keys)" ]
check "r0 SHELL of another kind falls back to /bin/zsh" [ "$(SHELL=/usr/local/bin/fish /bin/bash -c 'TERM_SH_LIB=1; . "$0"; login_shell' "$TERM_SH")" = /bin/zsh ]
check "r0 a bash login shell is used as it is" [ "$(SHELL=/bin/bash /bin/bash -c 'TERM_SH_LIB=1; . "$0"; login_shell' "$TERM_SH")" = /bin/bash ]

# ---------------------------------------------------------------- rule 1: tty + id
reset
new_tab
check "r1 screen by tty" ts screen "$TTY"
check "r1 screen by /dev tty" ts screen "/dev/$TTY"
check "r1 screen by session id" ts screen "$SID"
check "r1 title refused" [ "$(rc_of ts screen worker-one)" = 2 ]
printf 'fake-999' > "$(tabdir "$TTY")/tab"
check "r1 reused tty (other tab id) refused" [ "$(rc_of ts send "$TTY" hello --timeout 1)" = 4 ]
check "r1 nothing typed into the reused tty" [ -z "$(keys)" ]
reset; new_tab
printf 'other-program' > "$TERM_FAKE_DIR/proc/$PID/cmd"
check "r1 reused PID refused" [ "$(rc_of ts send "$SID" hello --timeout 1)" = 3 ]

# ---------------------------------------------------------------- rule 2: no hard-coded paths
for f in "$ROOT"/scripts/term/*.sh "$FAKE" "$ROOT"/scripts/tests/*.test.sh; do check "r2 ${f##*/} has no temp/user paths" lint_paths "$f"; done
printf 'X=/%s/%s/x\n' "$TMPWORD" foo > "$T/bad-paths"
check "r2 lint catches a temp path" not lint_paths "$T/bad-paths"
reset; new_tab
check "r2 registry lives under the home .local" [ -f "$REG" ]
check "r2 no stray temp files left in .local" [ -z "$(ls "$HOME_ROOT/.local" | grep -v -e '^registry.json$' -e '^config$')" ]

# ---------------------------------------------------------------- rule 3: wait for no dialog / empty box
reset; new_tab
check "r3 empty box -> sent" ts send "$TTY" "look at issue 7" --timeout 2
check "r3 text submitted" [ "$(sent)" = "look at issue 7" ]
reset; new_tab; dialog 1
check "r3 dialog open -> timeout" [ "$(rc_of ts send "$TTY" "look at issue 7" --timeout 1)" = 5 ]
check "r3 nothing typed while a dialog is open" [ -z "$(keys)" ]
check "r3 dialog not answered" [ ! -f "$(tabdir "$TTY")/answered" ]
reset; new_tab; : > "$(tabdir "$TTY")/busy"
check "r3 busy turn -> timeout" [ "$(rc_of ts send "$TTY" hi --timeout 1)" = 5 ]
check "r3 nothing typed while busy" [ -z "$(keys)" ]

# ---------------------------------------------------------------- rule 4: heads-up dismissed first
reset; new_tab
printf 'Heads up: something changed\n  0: Dismiss\n' > "$(tabdir "$TTY")/headsup"
check "r4 heads-up -> sent" ts send "$TTY" hello --timeout 2
check "r4 dismissed with 0 before typing" [ "$(keys | head -1)" = "type:0" ]
check "r4 text sent after dismiss" [ "$(sent)" = hello ]
reset; new_tab
printf 'Heads up: just words in the output\n' > "$(tabdir "$TTY")/body"
check "r4 plain words are not a notice" ts send "$TTY" hello --timeout 2
check "r4 no 0 typed without a notice" not has_key 'type:0'

reset; new_tab
printf 'old output line\n  0: Dismiss\n' > "$(tabdir "$TTY")/body"
check "r4 notice that does not go away -> refused" [ "$(rc_of ts send "$TTY" hello --timeout 2)" = 3 ]
check "r4 dismissed once only" [ "$(keys | grep -c 'type:0')" = 1 ]
check "r4 stray 0 taken back" [ -z "$(cat "$(tabdir "$TTY")/box")" ]

# ---------------------------------------------------------------- rule 5: ghost probe
reset; new_tab; put ghost "try running the tests"
check "r5 suggestion cleared and sent" ts send "$TTY" "real message" --timeout 2
check "r5 only our text submitted" [ "$(sent)" = "real message" ]
check "r5 probe was used" has_key 'type:x'
reset; new_tab; put box "half written thought"
check "r5 real draft -> timeout" [ "$(rc_of ts send "$TTY" "real message" --timeout 1)" = 5 ]
check "r5 draft kept intact" [ "$(cat "$(tabdir "$TTY")/box")" = "half written thought" ]
check "r5 nothing submitted over a draft" [ -z "$(sent)" ]
check "r5 probed once only" [ "$(keys | grep -c 'type:x')" = 1 ]
check "r5 state reports draft" [ "$(ts state "$TTY")" = draft ]

# ---------------------------------------------------------------- rule 6: swallowed Enter
reset; new_tab; put swallow 1
check "r6 one swallowed Enter recovered" ts send "$TTY" hello --timeout 2
check "r6 Enter pressed twice" [ "$(keys | grep -c 'key:cr')" = 2 ]
check "r6 text submitted" [ "$(sent)" = hello ]
reset; new_tab; put swallow 5
check "r6 two swallowed Enters -> error" [ "$(rc_of ts send "$TTY" hello --timeout 2)" = 5 ]
check "r6 never more than two Enters" [ "$(keys | grep -c 'key:cr')" = 2 ]

reset; new_tab; : > "$(tabdir "$TTY")/drop-typing"
check "r6 dropped write -> error" [ "$(rc_of ts send "$TTY" hello --timeout 2)" = 5 ]
check "r6 no Enter on a dropped write" not has_key 'key:cr'
check "r6 no SENT on a dropped write" not grep -q SENT "$T/out"

# ---------------------------------------------------------------- rule 7: login poke
reset; new_tab; dialog 1
check "r7 poke after a passing check" ts send "$TTY" "logged in, continue" --after cli-whoami --timeout 2
check "r7 answer typed into the free-text row" [ "$(cat "$(tabdir "$TTY")/answered")" = "logged in, continue" ]
check "r7 row picked by its number" has_key 'type:3'
reset; new_tab; dialog 1
check "r7 failing check -> timeout" [ "$(rc_of ts send "$TTY" "logged in" --after false --timeout 1)" = 5 ]
check "r7 nothing typed before the check passes" [ -z "$(keys)" ]
reset; new_tab; dialog 0
check "r7 dialog without free-text row -> timeout" [ "$(rc_of ts send "$TTY" "logged in" --after cli-whoami --timeout 1)" = 5 ]
check "r7 no option picked" [ ! -f "$(tabdir "$TTY")/answered" ]
reset; new_tab; dialog 1 "Allow this command to run?"
check "r7 dialog that is not a login prompt -> timeout" [ "$(rc_of ts send "$TTY" "logged in" --after cli-whoami --timeout 1)" = 5 ]
check "r7 nothing typed into a non-login dialog" [ -z "$(keys)" ]
reset term.login_dialog_re=allow; new_tab; dialog 1 "Allow this command to run?"
check "r7 login regex comes from config" ts send "$TTY" "go on" --after cli-whoami --timeout 2
reset; new_tab; dialog 1
D=$(tabdir "$TTY")
SWAP="printf 'Header\\nAllow this command to run?\\n  1. Yes\\n  3. Type something.\\nEnter to select\\n' > '$D/dialog'"
check "r7 dialog changed during the check -> timeout" [ "$(rc_of ts send "$TTY" "logged in" --after "$SWAP" --timeout 1)" = 5 ]
check "r7 screen re-read after the check: nothing typed" [ -z "$(keys)" ]
reset; new_tab; dialog 1
D=$(tabdir "$TTY")
DROP="printf 'Header\\nIs the login done now?\\n  1. Yes\\n  2. Not yet\\nEnter to select\\n' > '$D/dialog'"
check "r7 free-text row gone during the check -> timeout" [ "$(rc_of ts send "$TTY" "logged in" --after "$DROP" --timeout 1)" = 5 ]
check "r7 no row picked when the free-text row is gone" [ -z "$(keys)" ]

for c in "" true ":" " exit 0 " "echo done" echo "test 1"; do
  reset; new_tab; dialog 1
  check "r7 trivial check '$c' -> refused" [ "$(rc_of ts send "$TTY" "logged in" --after "$c" --timeout 1)" = 3 ]
  check "r7 refusal of trivial check '$c' names a real probe" grep -q "must prove the login" "$T/err"
  check "r7 nothing typed after trivial check '$c'" [ -z "$(keys)" ]
done
reset; new_tab; dialog 1
check "r7 a real probe is accepted" ts send "$TTY" "logged in" --after "cli-whoami --check" --timeout 2

# ---------------------------------------------------------------- rule 16: relay the owner's words
reset; new_tab; dialog 1 "Which branch should I use?"
check "r16 relay into the free-text row" ts send "$TTY" --relay "use the release branch, not main"
check "r16 the owner's words answered" [ "$(cat "$(tabdir "$TTY")/answered")" = "use the release branch, not main" ]
check "r16 free-text row picked by its number" [ "$(keys | head -1)" = "type:3" ]
check "r16 no listed option typed" [ -z "$(keys | grep -E '^type:[12]$')" ]
check "r16 Enter pressed once" [ "$(keys | grep -c 'key:cr')" = 1 ]
reset; new_tab; dialog 0 "Which branch should I use?"
check "r16 no free-text row -> refused" [ "$(rc_of ts send "$TTY" --relay "release")" = 3 ]
check "r16 nothing typed without a free-text row" [ -z "$(keys)" ]
check "r16 no option picked" [ ! -f "$(tabdir "$TTY")/answered" ]
reset; new_tab
check "r16 no dialog -> refused" [ "$(rc_of ts send "$TTY" --relay "release")" = 3 ]
check "r16 nothing typed without a dialog" [ -z "$(keys)" ]
reset; new_tab; dialog 1 "Which branch should I use?"; : > "$(tabdir "$TTY")/drop-typing"
check "r16 words not echoed -> refused" [ "$(rc_of ts send "$TTY" --relay "release")" = 3 ]
check "r16 no Enter when the words did not show" not has_key 'key:cr'
check "r16 nothing answered when the words did not show" [ ! -f "$(tabdir "$TTY")/answered" ]
reset; new_tab; dialog 1 "Use the release branch?"; : > "$(tabdir "$TTY")/drop-typing"
check "r16 words already on screen are not taken as echoed" [ "$(rc_of ts send "$TTY" --relay "release")" = 3 ]
check "r16 no Enter when only the question shows the words" not has_key 'key:cr'
reset; new_tab; dialog 1
check "r16 relay with another option -> usage error" [ "$(rc_of ts send "$TTY" --relay "x" --after cli-whoami)" = 2 ]
check "r16 multi-line words -> usage error" [ "$(rc_of ts send "$TTY" --relay "$(printf 'a\nb')")" = 2 ]
check "r16 nothing typed on a usage error" [ -z "$(keys)" ]

# ---------------------------------------------------------------- rule 17: cancel a dialog
reset; new_tab; dialog 1
check "r17 cancel an open dialog" ts send "$TTY" --cancel-dialog
check "r17 one Esc only" [ "$(keys)" = "key:esc" ]
check "r17 dialog closed, not answered" [ ! -f "$(tabdir "$TTY")/dialog" -a ! -f "$(tabdir "$TTY")/answered" ]
reset; new_tab
check "r17 no dialog -> refused" [ "$(rc_of ts send "$TTY" --cancel-dialog)" = 3 ]
check "r17 no Esc without a dialog" [ -z "$(keys)" ]
reset; new_tab; dialog 1; : > "$(tabdir "$TTY")/sticky-dialog"
check "r17 dialog still open after Esc -> error" [ "$(rc_of ts send "$TTY" --cancel-dialog)" = 5 ]
check "r17 Esc pressed once only" [ "$(keys | grep -c 'key:esc')" = 1 ]

# ---------------------------------------------------------------- rule 8: close only a finished session
reset; new_tab --issue 12; issue 12 final
check "r8 close a finished session" ts close "$TTY" --issue 12
check "r8 typed /exit then exit" [ "$(sent | tr '\n' ' ')" = "/exit exit " ]
check "r8 PID gone" not alive "$PID"
check "r8 tab closed" [ "$(mode)" = closed ]
check "r8 registry closed" [ "$(jq -r --arg s "$SID" '.[] | select(.session_id == $s) | .closed != null' "$REG")" = true ]
check "r8 never killed" [ ! -f "$TERM_FAKE_DIR/kills" ]
reset; new_tab --issue 12; issue 12 final
check "r8 issue taken from the registry" ts close "$TTY"
reset; new_tab; issue 12 final
check "r8 no issue anywhere -> usage error" [ "$(rc_of ts close "$TTY")" = 2 ]
check "r8 nothing typed without an issue" [ -z "$(keys)" ]
reset; new_tab --issue 12; issue 12 active
check "r8 no final comment on the issue -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 nothing typed without a final comment" [ -z "$(keys)" ]
check "r8 session left running" alive "$PID"
reset; new_tab --issue 12; issue 12 -
check "r8 issue with no home-log comment -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
reset; new_tab --issue 12; issue 12 final needs-test
check "r8 owner label on the issue -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 nothing typed while the owner label is on" [ -z "$(keys)" ]
reset; new_tab --issue 12
check "r8 issue unreadable on GitHub -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
reset; new_tab --issue 12; issue 12 final --repo other/place
check "r8 --repo picks the repo to check" ts close "$TTY" --repo other/place
reset; new_tab --issue 12; issue 12 final; issue 12 active --repo other/place
check "r8 --repo with an unfinished issue -> refused" [ "$(rc_of ts close "$TTY" --repo other/place)" = 3 ]
reset; new_tab --issue 12; ISSUE_RUN=run-of-an-earlier-worker issue 12 final
check "r8 only another run's final comment on the issue -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 the refusal names the other run's final" grep -q "of another run" "$T/err"
check "r8 nothing typed for another run's final" [ -z "$(keys)" ]
check "r8 that session is left running" alive "$PID"
reset; new_tab --issue 12; issue 12 final; dialog 1
check "r8 open question -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
reset; new_tab --issue 12; issue 12 final; put box "unsent note"
check "r8 real draft -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 draft kept" [ "$(cat "$(tabdir "$TTY")/box")" = "unsent note" ]
reset; new_tab --issue 12; issue 12 final; put status "2 shells"
check "r8 background work -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
reset; new_tab --issue 12; issue 12 final; : > "$(tabdir "$TTY")/busy"
check "r8 running turn -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 nothing typed on refusal" [ -z "$(keys)" ]
reset; new_tab --issue 12; issue 12 final
check "r8 wrong issue -> refused" [ "$(rc_of ts close "$TTY" --issue 13)" = 3 ]
reset; new_tab --issue 12; issue 12 final; : > "$(tabdir "$TTY")/linger"
check "r8 lingering PID -> reported, not force-closed" [ "$(rc_of ts close "$TTY")" = 5 ]
check "r8 lingering PID still alive" alive "$PID"
check "r8 lingering PID never signalled" [ ! -f "$TERM_FAKE_DIR/kills" ]
check "r8 shell left open" [ "$(mode)" = shell ]

entry_open() { [ "$(jq -r --arg s "$SID" '.[] | select(.session_id == $s) | .closed == null' "$REG")" = true ]; }
gone() { rm -rf "$TERM_FAKE_DIR/proc/$PID"; put mode shell; }   # the session ended on its own: the tab shows its shell
reset; new_tab --issue 12; issue 12 final; rm -rf "$TERM_FAKE_DIR/proc/$PID"; put box "typed by hand"
check "r8 session gone on its own, a box still on screen -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 nothing typed into a tab that still shows a box" [ -z "$(keys)" ]
check "r8 that draft intact" [ "$(cat "$(tabdir "$TTY")/box")" = "typed by hand" ]
check "r8 its entry stays open" entry_open
reset; new_tab --issue 12; issue 12 final; gone
check "r8 session gone on its own, a lone shell at an empty prompt -> closed" ts close "$TTY"
check "r8 only exit was typed there" [ "$(sent | tr '\n' ' ')" = "exit " ]
check "r8 that tab closed" [ "$(mode)" = closed ]
reset; new_tab --issue 12; issue 12 final; gone; put box "git push --force"
check "r8 session gone, a command half typed at the prompt -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 nothing typed after the half-typed command" [ -z "$(keys)" ]
check "r8 nothing submitted there" [ -z "$(sent)" ]
check "r8 its entry stays open (half-typed command)" entry_open
other_program() { mkdir -p "$TERM_FAKE_DIR/proc/777"; printf '%s' "$1" > "$TERM_FAKE_DIR/proc/777/cmd"; printf '%s' "$TTY" > "$TERM_FAKE_DIR/proc/777/tty"; }
for prog in "vim notes.md" "ssh build-host" "python3" "/bin/bash"; do
  reset; new_tab --issue 12; issue 12 final; gone; other_program "$prog"
  check "r8 session gone, $prog runs in the tab -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
  check "r8 nothing typed into $prog" [ -z "$(keys)" ]
  check "finished: session gone, $prog runs in the tab -> keep:shell" [ "$(ts finished | awk '{ print $4 }')" = keep:shell ]
  check "finished: and types nothing into $prog" [ -z "$(keys)" ]
done
reset; new_tab --issue 12; issue 12 final; gone; rm -rf "$TERM_FAKE_DIR/proc/$((PID + 5000))"
check "r8 session gone and no shell seen on the tty -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
reset; new_tab --issue 12; issue 12 final; other_program "vim notes.md"
check "r8 a live session closes, but exit is not typed beside another program" ts close "$TTY"
check "r8 only /exit was typed" [ "$(sent | tr '\n' ' ')" = "/exit " ]
check "r8 that shell is left open" [ "$(mode)" = shell ]
reset; new_tab --issue 12; issue 12 final; jq 'map(.pid = null)' "$REG" > "$T/r.json" && mv "$T/r.json" "$REG"
check "r8 a tab still starting (no process recorded) -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r8 nothing typed into the starting tab" [ -z "$(keys)" ]
check "r8 the starting session runs on" alive "$PID"
check "r8 its entry stays open (starting)" entry_open
check "finished: a tab still starting -> keep:starting" [ "$(ts finished | awk '{ print $4 }')" = keep:starting ]

# ---------------------------------------------------------------- finished: which tabs close would accept (read only)
verdict() { ts finished 2>/dev/null | awk -v t="$TTY" '$1 == t { print $4 }'; }
untouched_by_finished() { # the verdict equals $1, and finished sent no key and left the registry as it was
  local before v
  before=$(cksum < "$REG"); v=$(verdict)
  [ "$v" = "$1" ] && [ -z "$(keys)" ] && [ "$(cksum < "$REG")" = "$before" ]
}
reset; new_tab --issue 12; issue 12 final
check "finished: a finished worker is closable" [ "$(ts finished)" = "$TTY $SID 12 closable" ]
check "finished: no key, no registry write" untouched_by_finished closable
check "finished: the session still runs" alive "$PID"
check "finished: --json names the repo of the issue" [ "$(ts finished --json | jq -r '"\(.tty) \(.session_id) \(.issue) \(.repo) \(.role) \(.verdict)"')" = "$TTY $SID 12 test/home worker closable" ]
check "finished: close then accepts that tab" ts close "$TTY"
check "finished: a closed entry is not listed" [ -z "$(ts finished)" ]
reset; new_tab --issue 12; issue 12 active
check "finished: no final comment -> keep:no-final" untouched_by_finished keep:no-final
reset; new_tab --issue 12; issue 12 -
check "finished: no home-log comment -> keep:no-final" untouched_by_finished keep:no-final
reset; new_tab --issue 12; ISSUE_RUN=run-of-an-earlier-worker issue 12 final
check "finished: only another run's final comment -> keep:other-run" untouched_by_finished keep:other-run
jq --arg b "<!-- home-log run=$SID state=final -->" '.comments += [{id: 3, body: $b}]' "$GH_STUB_DIR/test__home/issues/12.json" > "$T/i.json" && mv "$T/i.json" "$GH_STUB_DIR/test__home/issues/12.json"
check "finished: this run's final beside another run's -> closable" untouched_by_finished closable
reset; new_tab --issue 12; issue 12 final; jq 'map(.adopted = true)' "$REG" > "$T/r.json" && mv "$T/r.json" "$REG"
check "finished: the owner's own tab (adopted) -> keep:owner-tab" untouched_by_finished keep:owner-tab
check "r15 close of a recorded adopted tab without --adopt -> refused" [ "$(rc_of ts close "$TTY")" = 3 ]
check "r15 nothing typed into it" [ -z "$(keys)" ]
check "r15 the same tab closes with --adopt" ts close "$TTY" --adopt
session_file() { # session_file <pid> <session id>: the session file Claude Code keeps for a live session
  mkdir -p "$TERM_FAKE_DIR/profiles/p/sessions"
  jq -n --argjson p "$1" --arg s "$2" '{pid: $p, sessionId: $s, cwd: "/x", status: "idle"}' > "$TERM_FAKE_DIR/profiles/p/sessions/$1.json"
}
reset; new_tab --issue 12; issue 12 final; session_file "$PID" "$SID"
check "finished: the session file names the recorded id -> closable" untouched_by_finished closable
session_file "$PID" abcdefab-cdef-4abc-8def-abcdefabcd09
check "finished: the session moved to another id (as after /clear) -> keep:moved" untouched_by_finished keep:moved
reset; new_tab --issue 12; issue 12 final
jq --arg n abcdefab-cdef-4abc-8def-abcdefabcd09 'map(. + {moved_from: .session_id, session_id: $n})' "$REG" > "$T/r.json" && mv "$T/r.json" "$REG"
check "finished: an entry that already followed a move -> keep:moved" [ "$(ts finished | awk '{ print $4 }')" = keep:moved ]
reset; new_tab --issue 12; issue 12 final needs-test
check "finished: owner label -> keep:owner-question" untouched_by_finished keep:owner-question
reset; new_tab --issue 12
check "finished: issue unreadable -> unsure:issue-unreadable" untouched_by_finished unsure:issue-unreadable
reset; new_tab
check "finished: no issue -> keep:no-issue" untouched_by_finished keep:no-issue
reset; new_tab --issue 12; issue 12 final; dialog 1
check "finished: open dialog -> keep:dialog" untouched_by_finished keep:dialog
check "finished: the dialog is not answered" [ ! -f "$(tabdir "$TTY")/answered" ]
reset; new_tab --issue 12; issue 12 final; : > "$(tabdir "$TTY")/busy"
check "finished: running turn -> keep:busy" untouched_by_finished keep:busy
reset; new_tab --issue 12; issue 12 final; put status "2 shells"
check "finished: background work -> keep:background" untouched_by_finished keep:background
reset; new_tab --issue 12; issue 12 final; put box "unsent note"
check "finished: text in the box -> unsure:box, no probe" untouched_by_finished unsure:box
check "finished: that text is intact" [ "$(cat "$(tabdir "$TTY")/box")" = "unsent note" ]
check "finished: close itself still refuses that draft" [ "$(rc_of ts close "$TTY")" = 3 ]
reset; new_tab --issue 12; issue 12 final; put ghost "a suggestion"
check "finished: a suggestion is unsure:box too (only close probes)" untouched_by_finished unsure:box
check "finished: close accepts it after its own probe" ts close "$TTY"
reset; new_tab --issue 12; issue 12 final
printf 'Heads up: something changed\n  0: Dismiss\n' > "$(tabdir "$TTY")/headsup"
check "finished: a notice -> unsure:notice, not dismissed" untouched_by_finished unsure:notice
check "finished: the notice is still there" [ -f "$(tabdir "$TTY")/headsup" ]
reset; new_tab --issue 12; issue 12 final; put mode shell
check "finished: no input box on a live session -> unsure:no-box" untouched_by_finished unsure:no-box
reset; new_tab --issue 12; issue 12 final; rm -rf "$TERM_FAKE_DIR/proc/$PID"; put mode shell
check "finished: the session ended on its own -> closable" untouched_by_finished closable
put box "git push --force"
check "finished: ended on its own, a command half typed at the prompt -> keep:shell" untouched_by_finished keep:shell
check "finished: that command is intact" [ "$(cat "$(tabdir "$TTY")/box")" = "git push --force" ]
reset; new_tab --issue 12; issue 12 active; rm -rf "$TERM_FAKE_DIR/proc/$PID"
check "finished: ended on its own but the issue is not final -> keep:no-final" untouched_by_finished keep:no-final
reset; new_tab --issue 12; issue 12 final; printf 'other-program' > "$TERM_FAKE_DIR/proc/$PID/cmd"
check "finished: another program under the recorded pid -> unsure:process" untouched_by_finished unsure:process
reset; new_tab --issue 12; issue 12 final; put mode closed
check "finished: the tab is gone -> keep:tab-gone" untouched_by_finished keep:tab-gone
reset; new_tab --issue 12; issue 12 final; printf 'fake-999' > "$(tabdir "$TTY")/tab"
check "finished: another tab on that tty -> keep:tab-gone" untouched_by_finished keep:tab-gone
reset; new_tab --issue 12; issue 12 final
check "finished: the calling session is kept" [ "$(CLAUDE_CODE_SESSION_ID=$SID /bin/bash "$TERM_SH" finished | awk '{ print $4 }')" = keep:caller ]
CHILD="$T/child home"; mkdir -p "$CHILD"; printf 'repo=test/child\n' > "$CHILD/home.config"
child_tab() { local out; out=$(ts open "$CHILD" --role orchestrator --issue 5) || return 1; SID=${out%% *}; out=${out#* }; TTY=${out%% *}; PID=${out#* }; }
reset; child_tab; issue 5 final --repo test/child
check "finished: an orchestrator tab is judged in its own home's repo" [ "$(ts finished --json | jq -r '"\(.repo) \(.verdict)"')" = "test/child closable" ]
reset; child_tab; ISSUE_RUN=run-of-its-worker issue 5 final --repo test/child
check "finished: an orchestrator tab whose issue a worker's run finished -> unsure:other-run" untouched_by_finished unsure:other-run
check "finished: close accepts that orchestrator tab on the owner's or a model's word" ts close "$TTY" --repo test/child
reset; child_tab; issue 5 final; issue 5 active --repo test/child
check "finished: never judged against this home's issue of the same number" untouched_by_finished keep:no-final
reset; child_tab; issue 5 final
check "finished: the child's issue unreadable -> unsure" untouched_by_finished unsure:issue-unreadable
reset; out=$(ts open "$WORK" --role orchestrator --issue 5); TTY=$(echo "$out" | awk '{ print $2 }'); issue 5 final
check "finished: an orchestrator tab whose folder names no repo -> unsure:issue-repo" untouched_by_finished unsure:issue-repo
reset; new_tab --issue 12; issue 12 final; A=$TTY; new_tab --issue 13; issue 13 active; new_tab
check "finished: one line per open tab of the registry" [ "$(ts finished | awk '{ print $3 ":" $4 }' | tr '\n' ' ')" = "12:closable 13:keep:no-final -:keep:no-issue " ]
hand_tab_plain() { mkdir -p "$TERM_FAKE_DIR/tabs/ttyh9" "$TERM_FAKE_DIR/proc/709"; printf 'hand-9' > "$TERM_FAKE_DIR/tabs/ttyh9/tab"; printf claude > "$TERM_FAKE_DIR/tabs/ttyh9/mode"
  printf claude > "$TERM_FAKE_DIR/proc/709/cmd"; printf ttyh9 > "$TERM_FAKE_DIR/proc/709/tty"; }
hand_tab_plain
check "finished: a tab outside the registry is never listed" sh -c '[ "$(printf "%s\n" "$1" | grep -c .)" = 3 ] && ! printf "%s\n" "$1" | grep -q ttyh9' _ "$(ts finished)"
check "finished: an option it does not know -> usage" [ "$(rc_of ts finished --force)" = 2 ]
check "finished: works from a Codex session" [ "$(env CODEX_THREAD_ID=thread-1 /bin/bash "$TERM_SH" finished | grep -c .)" = 3 ]
reset; printf '%s\n' terminal_helpers=off > "$HOME_ROOT/.local/config"
check "finished: helpers off -> exit 3" [ "$(rc_of ts finished)" = 3 ]

# ---------------------------------------------------------------- rule 9: park
reset; new_tab --issue 21; dialog 1
check "r9 park with an open question" ts park "$TTY"
check "r9 home-log checkpoint called" grep -q "^checkpoint 21 --run-id $SID --park --question Header Is the login done now? --text Parked by term.sh. Resume: cd .* --resume $SID" "$T/home-log.calls"
check "r9 dialog cancelled, not answered" [ ! -f "$(tabdir "$TTY")/answered" ]
check "r9 session exited" not alive "$PID"
check "r9 registry closed and parked" [ "$(jq -r --arg s "$SID" '.[] | select(.session_id == $s) | (.closed != null and .parked)' "$REG")" = true ]
reset; new_tab --issue 21; put box "my own unsent words"
check "r9 real draft -> refused" [ "$(rc_of ts park "$TTY")" = 3 ]
check "r9 home-log not called" [ ! -f "$T/home-log.calls" ]
check "r9 session still running" alive "$PID"
check "r9 draft kept" [ "$(cat "$(tabdir "$TTY")/box")" = "my own unsent words" ]
reset; new_tab --issue 21; touch "$T/home-log.fail"
check "r9 home-log failure -> refused, session kept" [ "$(rc_of ts park "$TTY")" = 3 ]
check "r9 session kept after home-log failure" alive "$PID"

reset; new_tab --issue 22; : > "$(tabdir "$TTY")/busy"
check "r9 running turn -> refused" [ "$(rc_of ts park "$TTY")" = 3 ]
check "r9 busy refusal says why" grep -q "session is busy; park it when idle" "$T/err"
check "r9 running turn never interrupted" [ -z "$(keys)" ]
check "r9 busy session still running" alive "$PID"
check "r9 home-log not called for a busy session" [ ! -f "$T/home-log.calls" ]
reset; new_tab --issue 22
check "r9 idle session parked without a question" ts park "$TTY"
check "r9 park without a question" grep -q "^checkpoint 22 --run-id $SID --park --text Parked by term.sh" "$T/home-log.calls"
check "r9 idle session exited" not alive "$PID"

# park follows a session that moved to a new id in its own process (as after /clear)
NSID="0a1b2c3d-9999-4222-8333-444455556666"
sfile() { # sfile <pid> <session id>: the session file of that process, under the profile folder "work"
  mkdir -p "$TERM_FAKE_DIR/profiles/work/sessions"
  jq -n --argjson pid "$1" --arg sid "$2" '{pid: $pid, sessionId: $sid, status: "idle"}' > "$TERM_FAKE_DIR/profiles/work/sessions/$1.json"
}
reset launch.profile_flag=-p launch.profile.worker=work; new_tab --issue 21; sfile "$PID" "$NSID"
check "r9 park of a session that moved to a new id" ts park "$TTY"
check "r9 the run on the issue keeps its first id, the resume line names the new one" \
  grep -q "^checkpoint 21 --run-id $SID --park --text Parked by term.sh. Resume: cd .* -p 'work' --resume $NSID$" "$T/home-log.calls"
check "r9 the entry follows the session" [ "$(jq -r '.[0] | "\(.session_id) \(.moved_from) \(.parked)"' "$REG")" = "$NSID $SID true" ]
check "r9 it was ended with /exit" [ "$(sent | head -1)" = /exit ]
out=$(ts resume "$NSID" 2>"$T/err")
check "r9 resume by the new id reopens it" [ "$(echo "$out" | awk '{ print $1 }')" = "$NSID" ]
check "r9 the old id is no longer a target" [ "$(rc_of ts resume "$SID")" = 4 ]
reset; new_tab --issue 21; sfile "$PID" "$NSID"
check "r9 moved, no profile flag: a tab this home opened keeps its recorded line for the new id" ts park "$TTY"
check "r9 that line names the new id and no profile" \
  grep -q "^checkpoint 21 --run-id $SID --park --text Parked by term.sh. Resume: cd '$WORK' && claude --resume $NSID$" "$T/home-log.calls"
reset; new_tab --issue 21; sfile "$PID" "$NSID"; mkdir "$HOME_ROOT/.local/registry.lock"
check "r9 moved, but the registry cannot be written -> refused" [ "$(rc_of ts park "$TTY")" = 3 ]
rmdir "$HOME_ROOT/.local/registry.lock"
check "r9 nothing typed on that refusal" [ -z "$(keys)" ]
check "r9 home-log not called on that refusal" [ ! -f "$T/home-log.calls" ]
check "r9 the entry keeps its id on that refusal" [ "$(jq -r '.[0].session_id' "$REG")" = "$SID" ]
reset launch.profile_flag=-p launch.profile.worker=work; new_tab --issue 21; sfile "$PID" "$SID"
ts park "$TTY" >/dev/null 2>&1
check "r9 a session file naming the same id changes nothing" [ "$(jq -r '.[0] | "\(.session_id) \(.moved_from)"' "$REG")" = "$SID null" ]

# ---------------------------------------------------------------- rule 10: resume
reset; new_tab --issue 21; dialog 1
ts park "$TTY" >/dev/null 2>&1
OLD=$TTY
out=$(ts resume "$SID" 2>"$T/err"); rc=$?
check "r10 resume works" [ "$rc" = 0 ]
NEWTTY=$(echo "$out" | awk '{ print $2 }')
check "r10 same session id" [ "$(echo "$out" | awk '{ print $1 }')" = "$SID" ]
check "r10 new tab" [ -n "$NEWTTY" -a "$NEWTTY" != "$OLD" ]
check "r10 no open question on the issue -> continue prompt" grep -q -- "--resume $SID 'You were resumed. Continue where you stopped.'" "$TERM_FAKE_DIR/launches"
check "r10 registry reopened" [ "$(jq -r --arg s "$SID" '.[] | select(.session_id == $s) | (.closed == null and .tty == "'"$NEWTTY"'")' "$REG")" = true ]
check "r10 resume of an open session -> refused" [ "$(rc_of ts resume "$SID")" = 3 ]
check "r10 unknown session -> not found" [ "$(rc_of ts resume deadbeef-0000)" = 4 ]
run_comment() { # run_comment <n> <run id> <extra line or ""> : the issue holds that run's home-log comment
  issue "$1" -
  jq --arg b "$(printf '<!-- home-log run=%s state=parked -->\n**home-log** . parked\n- run: %s\n%s\n' "$2" "$2" "$3")" \
    '.comments += [{id: 3, body: $b}]' "$GH_STUB_DIR/test__home/issues/$1.json" > "$T/i.json" &&
    mv "$T/i.json" "$GH_STUB_DIR/test__home/issues/$1.json"
}
parked() { # parked: a fresh session on issue 21, parked; sets SID
  reset; new_tab --issue 21; ts park "$TTY" >/dev/null 2>&1
}
parked; run_comment 21 "$SID" "- Open question for the owner: Which branch?"
check "r10 open question -> resume works" ts resume "$SID"
check "r10 open question -> re-ask prompt" grep -q -- "--resume $SID 'You were parked.*Re-ask your open question" "$TERM_FAKE_DIR/launches"
parked; run_comment 21 "$SID" ""; run_comment 21 other-run "- Open question for the owner: Not this run's"
jq --arg b "<!-- home-log run=$SID state=parked -->" '.comments += [{id: 4, body: $b}]' "$GH_STUB_DIR/test__home/issues/21.json" > "$T/i.json" && mv "$T/i.json" "$GH_STUB_DIR/test__home/issues/21.json"
check "r10 another run's question -> resume works" ts resume "$SID"
check "r10 another run's question -> continue prompt" grep -q -- "--resume $SID 'You were resumed. Continue where you stopped.'" "$TERM_FAKE_DIR/launches"
parked; run_comment 21 "$SID" "- Open question for the owner: Which branch?"
check "r10 --message replaces the default" ts resume "$SID" --message "The timer fired; run the next step."
check "r10 --message text sent" grep -q -- "--resume $SID 'The timer fired; run the next step.'" "$TERM_FAKE_DIR/launches"
check "r10 --message: no re-ask prompt" not grep -q "Re-ask" "$TERM_FAKE_DIR/launches"
parked
check "r10 --silent works" ts resume "$SID" --silent
check "r10 --silent sends no message" grep -q -- "--resume $SID\$" "$TERM_FAKE_DIR/launches"
parked
check "r10 --message with --silent -> usage" [ "$(rc_of ts resume "$SID" --message x --silent)" = 2 ]
check "r10 empty --message -> usage" [ "$(rc_of ts resume "$SID" --message "")" = 2 ]
check "r10 unknown option -> usage" [ "$(rc_of ts resume "$SID" --loud)" = 2 ]
check "r10 refused resume leaves the session closed" [ "$(jq -r --arg s "$SID" '.[] | select(.session_id == $s) | .closed != null' "$REG")" = true ]

# ---------------------------------------------------------------- rule 11: memory and worker cap
reset
check "r11 open with enough memory" ts open "$WORK"
reset; echo 5 > "$TERM_FAKE_DIR/mem_free"
check "r11 memory pressure -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r11 no tab opened under pressure" [ ! -f "$TERM_FAKE_DIR/launches" ]
reset; echo "n/a" > "$TERM_FAKE_DIR/mem_free"
check "r11 memory unreadable -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r11 no tab opened when memory is unreadable" [ ! -f "$TERM_FAKE_DIR/launches" ]
reset term.min_free_pct=0; echo "n/a" > "$TERM_FAKE_DIR/mem_free"
check "r11 min_free_pct=0 skips the memory check" ts open "$WORK"
reset term.max_workers=2
ts open "$WORK" >/dev/null 2>&1; ts open "$WORK" >/dev/null 2>&1
check "r11 cap reached -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r11 orchestrator not counted as a worker" ts open "$WORK" --role orchestrator
check "r11 cap: two workers and the orchestrator launched, no third worker" [ "$(grep -c . "$TERM_FAKE_DIR/launches")" = 3 ]
rm -rf "$TERM_FAKE_DIR/proc/60001"
check "r11 dead worker frees a slot" ts open "$WORK"
reset term.max_workers=1
jq -nc '[{session_id: "stale-reservation", pid: null, tty: null, closed: null, role: "worker", match: "x", opened: "2000-01-01T00:00:00Z"}]' > "$REG"
check "r11 stale reservation does not hold a slot" ts open "$WORK"
launch_count() { grep -c . "$TERM_FAKE_DIR/launches"; }
reset term.max_workers=1; new_tab --issue 21; ts park "$TTY" >/dev/null 2>&1; PARKED=$SID; new_tab --issue 22; n=$(launch_count)
check "r11 worker resume at a full cap -> refused" [ "$(rc_of ts resume "$PARKED")" = 3 ]
check "r11 nothing launched by a resume at a full cap" [ "$(launch_count)" = "$n" ]
check "r11 a resume refused at the cap leaves the entry closed" [ "$(jq -r --arg s "$PARKED" '.[] | select(.session_id == $s) | .closed != null' "$REG")" = true ]
parked; n=$(launch_count); echo 5 > "$TERM_FAKE_DIR/mem_free"
check "r11 resume under memory pressure -> refused" [ "$(rc_of ts resume "$SID")" = 3 ]
check "r11 nothing launched by a resume under memory pressure" [ "$(launch_count)" = "$n" ]
reset; printf '%s\n' terminal_helpers=off > "$HOME_ROOT/.local/config"
check "r11 helpers off -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r11 helpers off -> survey refused too" [ "$(rc_of ts survey)" = 3 ]
reset launch.command=codex
check "r11 Codex orchestrator (launch.command=codex) -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r11 Codex orchestrator: no tab opened" sh -c '[ -z "$(ls "$1/tabs" 2>/dev/null)" ]' _ "$TERM_FAKE_DIR"
reset launch.command=claude
check "r11 launch.command=claude -> open works" ts open "$WORK"
reset
check "r11 called from a Codex session (CODEX_THREAD_ID) -> refused" [ "$(rc_of env CODEX_THREAD_ID=thread-1 /bin/bash "$TERM_SH" open "$WORK")" = 3 ]
check "r11 called from a Codex session: no tab opened" sh -c '[ -z "$(ls "$1/tabs" 2>/dev/null)" ]' _ "$TERM_FAKE_DIR"
reset; new_tab   # a Codex thread with no record of its own still reads the tabs
check "r11 called from an unmapped Codex session: survey lists the tab" grep -q "$TTY" <(env CODEX_THREAD_ID=thread-1 /bin/bash "$TERM_SH" survey)
check "r11 called from an unmapped Codex session: state works" [ "$(env CODEX_THREAD_ID=thread-1 /bin/bash "$TERM_SH" state "$TTY")" = idle ]

# ---------------------------------------------------------------- rule 12: kill exact PID after checking it
signals_outside_pid_kill() { # code lines (comments dropped) outside pid_kill and the be_kill primitive that signal or call them
  awk '/^pid_kill\(\)/ { inside = 1 } inside { if (/^}/) inside = 0; next } /^be_kill\(\)/ { next }
    { sub(/(^|[[:space:]])#.*/, "") } /(^|[^A-Za-z0-9_])(p?kill(all)?|pid_kill|be_kill)([^A-Za-z0-9_]|$)/ { print NR ": " $0 }' "$1" | grep .
}
check "r12 no verb signals a PID (no kill or pid_kill outside pid_kill)" not signals_outside_pid_kill "$TERM_SH"
(
  export TERM_SH_LIB=1 TERM_SH_BACKEND=real
  . "$TERM_SH"
  sleep 300 & good=$!
  sleep 301 & other=$!
  pid_kill "$good" "sleep 300" 2>/dev/null; wait "$good" 2>/dev/null
  if kill -0 "$good" 2>/dev/null; then echo "matching PID survived"; fi
  pid_kill "$other" "sleep 300" 2>/dev/null && echo "mismatch was signalled"
  kill -0 "$other" 2>/dev/null || echo "mismatched PID died"
  pid_kill "not-a-pid" "sleep" 2>/dev/null && echo "non-number accepted"
  kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
) > "$T/r12" 2>&1
check "r12 real process: match killed, mismatch refused ($(tr '\n' ';' < "$T/r12"))" [ ! -s "$T/r12" ]

# ---------------------------------------------------------------- rule 13: no underscore function names
for f in "$ROOT"/scripts/term/*.sh "$FAKE" "$ROOT"/scripts/tests/*.test.sh; do check "r13 ${f##*/} has no underscore functions" lint_underscore "$f"; done
printf '%s() { :; }\n' "_hidden" > "$T/bad-fn"
check "r13 lint catches an underscore function" not lint_underscore "$T/bad-fn"

# ---------------------------------------------------------------- rule 14: launch values from .local/config
reset launch.profile.worker=wprof launch.profile.orchestrator=oprof launch.model=opus launch.profile_flag=-p
new_tab
check "r14 worker profile and model alias" grep -q "&& claude -p 'wprof' --model 'opus' --session-id $SID" "$TERM_FAKE_DIR/launches"
ts open "$WORK" --role orchestrator >/dev/null 2>&1
check "r14 orchestrator profile" grep -q "claude -p 'oprof' --model 'opus' --session-id" "$TERM_FAKE_DIR/launches"
reset launch.profile.worker=wprof launch.model=sonnet
new_tab
check "r14 no profile flag -> profile not passed" grep -q "&& claude --model 'sonnet' --session-id $SID\$" "$TERM_FAKE_DIR/launches"
reset launch.command=mycli launch.profile_flag=--profile launch.profile.worker=w2
new_tab
check "r14 launch command and flag from config" grep -q "&& mycli --profile 'w2' --session-id $SID\$" "$TERM_FAKE_DIR/launches"
reset
new_tab --brief "run issue #4"
check "r14 unset profile -> plain command" grep -q "&& claude --session-id $SID 'run issue #4'\$" "$TERM_FAKE_DIR/launches"
MODEL_ID="claude-opus-4""-1-2025""0805"
reset "launch.model=$MODEL_ID"
check "r14 pinned model id -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r14 nothing launched with a pinned id" [ ! -f "$TERM_FAKE_DIR/launches" ]
reset "launch.command=claude --model $MODEL_ID"
check "r14 launch command with extra words -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r14 nothing launched with extra words in the command" [ ! -f "$TERM_FAKE_DIR/launches" ]
reset "launch.profile_flag=-p x"
check "r14 profile flag with a value in it -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "r14 nothing launched with a value in the profile flag" [ ! -f "$TERM_FAKE_DIR/launches" ]
reset
cp "$HOME_ROOT/home.config" "$T/home.config.bak"
printf '%s\n' launch.command=othercli launch.profile_flag=-p launch.profile.worker=shared "launch.model=$MODEL_ID" >> "$HOME_ROOT/home.config"
new_tab
check "r14 launch keys in home.config are ignored" grep -q "&& claude --session-id $SID\$" "$TERM_FAKE_DIR/launches"
cp "$T/home.config.bak" "$HOME_ROOT/home.config"

# ---------------------------------------------------------------- registry: atomic and concurrent
reset term.max_workers=100
N=12; i=0; export TERM_SH_LOCK_TIMEOUT=30 TERM_SH_OPEN_WAIT=30
while [ $i -lt $N ]; do ts open "$WORK" --issue $((i + 1)) >"$T/par.$i" 2>&1 & i=$((i + 1)); done
wait
check "registry is a valid JSON array holding every entry after $N parallel writers" [ "$(jq 'if type == "array" then length else -1 end' "$REG")" = $N ]
check "every entry has tty and pid" [ "$(jq '[.[] | select(.tty != null and .pid != null)] | length' "$REG")" = $N ]
check "session ids unique" [ "$(jq '[.[].session_id] | unique | length' "$REG")" = $N ]
check "issues all recorded" [ "$(jq '[.[].issue] | unique | length' "$REG")" = $N ]
check "no lock or temp file left" [ -z "$(ls "$HOME_ROOT/.local" | grep -v -e '^registry.json$' -e '^config$')" ]
export TERM_SH_LOCK_TIMEOUT=1
cp "$REG" "$T/reg.before"
mkdir "$HOME_ROOT/.local/registry.lock"; echo $$ > "$HOME_ROOT/.local/registry.lock/pid"
check "held lock -> refused" [ "$(rc_of ts open "$WORK")" = 3 ]
check "held lock is not stolen" [ -d "$HOME_ROOT/.local/registry.lock" ]
check "registry unchanged under a held lock" cmp -s "$REG" "$T/reg.before"
rm -rf "$HOME_ROOT/.local/registry.lock"

# ---------------------------------------------------------------- survey: live tabs, not the registry
reset
new_tab
mkdir -p "$TERM_FAKE_DIR/tabs/ttyhand"; printf 'hand-1' > "$TERM_FAKE_DIR/tabs/ttyhand/tab"; printf 'claude' > "$TERM_FAKE_DIR/tabs/ttyhand/mode"
mkdir -p "$TERM_FAKE_DIR/proc/777"; printf 'claude' > "$TERM_FAKE_DIR/proc/777/cmd"; printf 'ttyhand' > "$TERM_FAKE_DIR/proc/777/tty"; printf '%s' "$T" > "$TERM_FAKE_DIR/proc/777/cwd"
out=$(ts survey)
check "survey lists the registered tab" out_has "$TTY $PID claude $SID $WORK"
check "survey sees a tab opened by hand" out_has "ttyhand 777 claude - $T"
check "survey --cwd finds the hand tab" ts survey --cwd "$T"
check "survey --cwd with no session -> exit 1" [ "$(rc_of ts survey --cwd "$HOME_ROOT")" = 1 ]
check "state idle" [ "$(ts state "$TTY")" = idle ]

# ---------------------------------------------------------------- rule 15: --adopt the owner's own tab
hand_tab() { # hand_tab <tty> <pid> <command line> [mode]: a tab the owner opened by hand (not in the registry)
  local d="$TERM_FAKE_DIR/tabs/$1"
  mkdir -p "$d" "$TERM_FAKE_DIR/proc/$2"
  printf 'hand-%s' "$1" > "$d/tab"; printf '%s' "${4:-claude}" > "$d/mode"; : > "$d/box"; printf '%s' "$2" > "$d/pid"
  printf '%s' "$3" > "$TERM_FAKE_DIR/proc/$2/cmd"; printf '%s' "$1" > "$TERM_FAKE_DIR/proc/$2/tty"
  printf '%s' "$WORK" > "$TERM_FAKE_DIR/proc/$2/cwd"
  mkdir -p "$TERM_FAKE_DIR/proc/$(($2 + 5000))"   # the tab's own login shell, as a real tab has
  printf '%s' -zsh > "$TERM_FAKE_DIR/proc/$(($2 + 5000))/cmd"; printf '%s' "$1" > "$TERM_FAKE_DIR/proc/$(($2 + 5000))/tty"
  printf '%s' "$WORK" > "$TERM_FAKE_DIR/proc/$(($2 + 5000))/cwd"
  TTY=$1; PID=$2
}
reg_len() { if [ -f "$REG" ]; then jq length "$REG"; else echo 0; fi; }
untouched() { # untouched <registry length>: nothing typed, nothing recorded, nothing signalled
  [ -z "$(keys)" ] && [ "$(reg_len)" = "$1" ] && [ ! -f "$TERM_FAKE_DIR/kills" ]
}
HSID="0a1b2c3d-1111-4222-8333-444455556666"
claim() { # claim <n> <run id>: the run has an active home-log comment on issue n
  mkdir -p "$GH_STUB_DIR/test__home/issues"
  jq -n --argjson n "$1" --arg body "<!-- home-log run=$2 state=active -->" \
    '{number: $n, title: "t", body: "", state: "open", state_reason: null, labels: [], created_at: "x", updated_at: "x",
      closed_at: null, author: "owner", comments: [{id: 1, body: $body}]}' > "$GH_STUB_DIR/test__home/issues/$1.json"
}

reset; hand_tab ttyh1 701 "claude"
check "r15 close --adopt without an issue" ts close ttyh1 --adopt
check "r15 typed /exit then exit" [ "$(sent | tr '\n' ' ')" = "/exit exit " ]
check "r15 adopted PID gone" not alive 701
check "r15 recorded as adopted and closed" [ "$(jq -r '.[0] | (.adopted == true and .closed != null and .tty == "ttyh1" and .pid == 701)' "$REG")" = true ]
check "r15 never killed" [ ! -f "$TERM_FAKE_DIR/kills" ]
reset; hand_tab ttyh1 701 "/usr/local/bin/claude --model opus"; issue 12 final
check "r15 close --adopt with a finished issue" ts close ttyh1 --adopt --issue 12
check "r15 issue recorded" [ "$(jq -r '.[0].issue' "$REG")" = 12 ]
reset; hand_tab ttyh1 702 "claude --resume $HSID"; claim 21 "$HSID"
check "r15 park --adopt" ts park ttyh1 --adopt --issue 21
check "r15 park wrote the resume command" grep -q "^checkpoint 21 --run-id $HSID --park --text Parked by term.sh. Resume: cd .* && 'claude' --resume $HSID" "$T/home-log.calls"
check "r15 parked entry adopted" [ "$(jq -r '.[0] | (.adopted == true and .parked == true and .session_id == "'"$HSID"'")' "$REG")" = true ]
check "r15 parked session exited" not alive 702
check "r15 parked entry bound to the issue" [ "$(jq -r '.[0].issue' "$REG")" = 21 ]
reset launch.profile_flag=--profile; hand_tab ttyh1 703 "claude --profile team --model opus --resume $HSID --verbose"; claim 21 "$HSID"
check "r15 park --adopt keeps launch flags" ts park ttyh1 --adopt --issue 21
check "r15 resume keeps profile and model" grep -q "Resume: cd .* && 'claude' --profile 'team' --model 'opus' --resume $HSID\$" "$T/home-log.calls"

reset; hand_tab ttyh1 701 "claude"
check "r15 hand tab without --adopt -> refused" [ "$(rc_of ts close ttyh1)" = 3 ]
check "r15 untouched without --adopt" untouched 0
check "r15 park without --adopt -> refused" [ "$(rc_of ts park ttyh1 --issue 21)" = 3 ]
check "r15 park untouched without --adopt" untouched 0
reset; new_tab --issue 12; issue 12 final
check "r15 --adopt by session id -> usage error" [ "$(rc_of ts close "$SID" --adopt)" = 2 ]
check "r15 --adopt on a registered tab -> usage error" [ "$(rc_of ts close "$TTY" --adopt)" = 2 ]
check "r15 registered tab untouched" untouched 1
reset; hand_tab ttyh1 703 "-zsh" shell
check "r15 shell-only tty -> not found" [ "$(rc_of ts close ttyh1 --adopt)" = 4 ]
check "r15 shell tty untouched" untouched 0
reset; hand_tab ttyh1 704 "claude-helper"
check "r15 other program named like claude -> not found" [ "$(rc_of ts close ttyh1 --adopt)" = 4 ]
reset; hand_tab ttyh1 705 "claude"; mkdir -p "$TERM_FAKE_DIR/proc/706"
printf 'claude' > "$TERM_FAKE_DIR/proc/706/cmd"; printf 'ttyh1' > "$TERM_FAKE_DIR/proc/706/tty"
check "r15 two claude PIDs on the tty -> refused" [ "$(rc_of ts close ttyh1 --adopt)" = 3 ]
check "r15 two PIDs untouched" untouched 0
check "r15 both PIDs alive" alive 705
reset; hand_tab ttyh1 701 "claude"; : > "$(tabdir "$TTY")/busy"
check "r15 running turn -> refused" [ "$(rc_of ts close ttyh1 --adopt)" = 3 ]
check "r15 busy untouched" untouched 0
reset; hand_tab ttyh1 701 "claude"; dialog 1
check "r15 open dialog -> refused" [ "$(rc_of ts close ttyh1 --adopt)" = 3 ]
check "r15 dialog untouched" untouched 0
reset; hand_tab ttyh1 701 "claude"; put status "1 background task"
check "r15 background work -> refused" [ "$(rc_of ts close ttyh1 --adopt)" = 3 ]
check "r15 background untouched" untouched 0
reset; hand_tab ttyh1 701 "claude"; put box "owner is typing"
check "r15 real draft -> refused" [ "$(rc_of ts close ttyh1 --adopt)" = 3 ]
check "r15 draft kept" [ "$(cat "$(tabdir "$TTY")/box")" = "owner is typing" ]
check "r15 recorded before the probe" [ "$(jq -r '.[0] | (.adopted == true and .closed == null)' "$REG")" = true ]
check "r15 draft session alive" alive 701
reset; hand_tab ttyh1 701 "claude"; issue 12 active
check "r15 issue without a final comment -> refused" [ "$(rc_of ts close ttyh1 --adopt --issue 12)" = 3 ]
check "r15 unfinished issue untouched" untouched 0
reset; hand_tab ttyh1 701 "claude"
check "r15 park without a session id -> refused" [ "$(rc_of ts park ttyh1 --adopt --issue 21)" = 3 ]
check "r15 park no-id untouched" untouched 0
check "r15 home-log not called" [ ! -f "$T/home-log.calls" ]
reset; hand_tab ttyh1 702 "claude --resume $HSID"
check "r15 park without an issue -> usage error" [ "$(rc_of ts park ttyh1 --adopt)" = 2 ]
check "r15 park no-issue untouched" untouched 0
reset; hand_tab ttyh1 702 "claude --resume $HSID"; issue 21 active
check "r15 park when the run has no comment on the issue -> refused" [ "$(rc_of ts park ttyh1 --adopt --issue 21)" = 3 ]
check "r15 refusal names home-log start" grep -qF "run 'scripts/home-log start 21 --run-id $HSID' first" "$T/err"
check "r15 no-comment untouched" untouched 0
check "r15 no-comment home-log not called" [ ! -f "$T/home-log.calls" ]
reset; hand_tab ttyh1 702 "claude --resume $HSID"; claim 21 "$HSID"; claim 22 "$HSID"; : > "$T/home-log.fail"
check "r15 park --adopt with a failing home-log -> refused" [ "$(rc_of ts park ttyh1 --adopt --issue 21)" = 3 ]
check "r15 failed park leaves the tab bound to no issue" [ "$(jq -r '.[0] | (.adopted == true and .issue == null and .closed == null)' "$REG")" = true ]
check "r15 failed park session alive" alive 702
rm -f "$T/home-log.fail"
check "r15 park after a failed park with another issue" ts park ttyh1 --adopt --issue 22
check "r15 second park bound to that issue" [ "$(jq -r '.[0] | (.issue == 22 and .parked == true)' "$REG")" = true ]
reset; hand_tab ttyh1 701 "claude"; issue 12 final; put box "owner is typing"
check "r15 close --adopt refused on a draft" [ "$(rc_of ts close ttyh1 --adopt --issue 12)" = 3 ]
check "r15 refused close leaves the tab bound to no issue" [ "$(jq -r '.[0] | (.adopted == true and .issue == null)' "$REG")" = true ]
reset; new_tab --issue 12; issue 12 final; issue 13 final
check "r15 an opened tab keeps its strict issue binding" [ "$(rc_of ts close "$TTY" --issue 13)" = 3 ]

echo "term.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
