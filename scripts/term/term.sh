#!/usr/bin/env bash
# term.sh: open, read, type into and close terminal tabs (iTerm2) for this home.
#
#   term.sh open <dir> [--issue N] [--role worker|orchestrator] [--brief TEXT | --brief-file F]
#                                    -> prints "<session_id> <tty> <pid>"
#   term.sh screen <target> [--lines N]
#   term.sh state  <target>          -> gone | dialog | headsup | busy | bg | draft | idle | shell
#   term.sh send   <target> <text> [--after "<check command>"] [--timeout S]
#   term.sh send   <target> --relay "<the owner's own words>"
#   term.sh send   <target> --cancel-dialog
#   term.sh park   <target> [--issue N] [--adopt] [--timeout S]
#   term.sh resume <session_id> [--message TEXT | --silent]
#   term.sh close  <target> [--issue N] [--adopt] [--repo OWNER/REPO] [--timeout S]
#   term.sh survey [--cwd DIR]       -> "<tty> <pid|-> <claude|shell> <session_id|-> <cwd>" per live tab
#
# <target> is a tty (ttys003 or /dev/ttys003) or a session id from .local/registry.json.
# A tab title is never accepted: titles drift.
#
# --adopt (close and park): the owner's own tab, opened by hand and not in the registry. Use it
# only when the owner named this tab or asked to close it. The target must be a tty; exactly one
# claude process must run on it (its exact PID, command line checked) and its screen must read.
# Every other check stays. Close with --adopt checks the issue when one is given and needs none
# otherwise; park with --adopt needs a session id on the process's command line (--session-id or
# --resume). The tab is recorded in the registry with "adopted": true before the first keystroke
# (a notice dismissal, a ghost probe or the exit command).
#
# Rules this file enforces (see openspec/specs/terminal-helpers in the base):
#  1 tabs are addressed by tty and verified against the recorded tab id and pid
#  2 every file it writes is under <home>/.local/
#  3 send waits for no dialog, no running turn and an empty input box
#  4 a "Heads up" notice ("0: Dismiss") is dismissed first
#  5 ghost probe: a box with text gets one probe character; exactly that character back means
#    the text was a suggestion (cleared, then send); anything else is a real draft (kept, wait)
#  6 after Enter the screen is re-read; a swallowed Enter is pressed once more, never twice
#  7 a dialog is answered only by send --after: once the check passes, the screen is read again,
#    and only a login dialog (term.login_dialog_re) that still has a free-text row is answered there.
#    The check must prove the login, e.g. a CLI identity call: an empty check, true, :, exit 0,
#    echo ... and test 1 are refused
#  8 close only on a finished session: the issue has a final home-log comment and no owner label
#    (checked on GitHub), no dialog, no running turn, no background work, an empty box; it types
#    /exit, verifies the PID is gone, exits the shell. A PID that lingers is reported, never killed
#  9 park writes the open question and the resume command to the issue, then exits; it refuses
#    when a real unsent draft exists or a turn is running (a running turn is never interrupted)
# 10 resume reopens the recorded session id with one message: --message TEXT replaces the default,
#    --silent sends none; the default asks it to re-ask its open question only when the run's
#    home-log comment on the issue holds "Open question for the owner", else to continue
# 11 open refuses under memory pressure, when memory cannot be read, or at the worker cap
# 12 a PID is signalled only by exact number, after its command line was checked
# 13 no function name starts with an underscore
# 14 the launch command, profile and model come from .local/config only; the model is an alias
# 15 --adopt takes only a tty with exactly one claude process on it and records the tab before acting
# 16 send --relay types the owner's own words into the free-text row of the dialog open on that tab
#    (picked by its number, as the login poke does), checks they show on screen, then presses Enter;
#    it refuses when no dialog or no free-text row is open and never picks a listed option
# 17 send --cancel-dialog presses Esc once on a dialog open on that tab (when the owner says to
#    dismiss it) and checks that the dialog closed
#
# Config (.local/config overrides home.config):
#   terminal_helpers=on            required for every verb
#   term.max_workers=4             open worker tabs allowed at once
#   term.min_free_pct=20           refuse to open below this free-memory percentage (0 = no check)
#   term.login_dialog_re           extended regex (case-insensitive) a dialog must match to be
#                                  answered by send --after (default: log in, sign in, session expired...)
#   labels.needs_owner             label of an issue waiting on the owner (default needs-owner)
# Launch keys, read from .local/config only (never home.config):
#   launch.command=claude          the command that starts a session (one word)
#   launch.profile_flag=           flag put before the profile value; empty = no profile is passed
#   launch.profile.orchestrator / launch.profile.worker   the profile value per role
#   launch.model                   passed as "--model <alias>" when set
# close reads the issue with gh (repo: --repo, else repo in home.config).
# Test seams: TERM_SH_BACKEND=fake (sources ../tests/stubs/term-fake), TERM_SH_POLL,
#   TERM_SH_SETTLE, TERM_SH_OPEN_WAIT, TERM_SH_EXIT_WAIT, TERM_SH_LOCK_TIMEOUT, TERM_SH_HOME_LOG.
# Exit: 0 ok, 2 usage, 3 refused by a rule, 4 tab or session not found, 5 timed out.
#
# bash 3.2 compatible. Needs jq and gh; the real backend needs osascript, ps, lsof, memory_pressure.

set -u
TERM_SH_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$TERM_SH_DIR/../lib/config"

LOCAL_DIR="$HOME_ROOT/.local"
REG="$LOCAL_DIR/registry.json"
LOCK="$LOCAL_DIR/registry.lock"
POLL=${TERM_SH_POLL:-2}
SETTLE=${TERM_SH_SETTLE:-1}
OPEN_WAIT=${TERM_SH_OPEN_WAIT:-30}
EXIT_WAIT=${TERM_SH_EXIT_WAIT:-30}
LOCK_TIMEOUT=${TERM_SH_LOCK_TIMEOUT:-20}
HOME_LOG=${TERM_SH_HOME_LOG:-$TERM_SH_DIR/../home-log}
CHUNK=200   # longer single writes are dropped silently by the terminal

RULE=$'\xe2\x94\x80'    # box border character
PROMPT=$'\xe2\x9d\xaf'  # input prompt character
NBSP=$'\xc2\xa0'
LOCK_HELD=0

die() { local c=$1; shift; echo "term.sh: $*" >&2; exit "$c"; }
note() { echo "term.sh: $*" >&2; }

# ------------------------------------------------------------------ real backend
# Every outside effect goes through a be_* function so tests can swap them.

osa_session() { # osa_session <screen|type|cr|esc|bs> <tty> <tab id or ""> [text]
  osascript - "$1" "/dev/$2" "$3" "${4:-}" <<'OSA'
on run argv
  set act to item 1 of argv
  set tt to item 2 of argv
  set tabid to item 3 of argv
  set txt to item 4 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if (tty of s) is tt and (tabid is "" or (id of s) is tabid) then
            if act is "screen" then return (contents of s) as text
            if act is "type" then tell s to write text txt newline NO
            if act is "cr" then tell s to write text (character id 13) newline NO
            if act is "esc" then tell s to write text (character id 27) newline NO
            if act is "bs" then tell s to write text (character id 127) newline NO
            return "TERM-SH-OK"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return "TERM-SH-NOTFOUND"
end run
OSA
}

iterm_running() { [ "$(osascript -e 'application "iTerm2" is running' 2>/dev/null)" = "true" ]; }

be_screen() { # be_screen <tty> <tab> -> screen text; rc 4 when the tab is gone
  local out
  out=$(osa_session screen "$1" "$2") || return 4
  [ "$out" = "TERM-SH-NOTFOUND" ] && return 4
  printf '%s\n' "$out"
}
be_type() { [ "$(osa_session type "$1" "$2" "$3")" = "TERM-SH-OK" ] || return 4; }
be_key() { [ "$(osa_session "$3" "$1" "$2")" = "TERM-SH-OK" ] || return 4; }   # be_key <tty> <tab> cr|esc|bs

be_open() { # be_open <command line> -> "<tab id> <tty>"; types the command into the new tab only
  local out
  out=$(osascript - "$1" <<'OSA'
on run argv
  tell application "iTerm2"
    if (count of windows) = 0 then
      set w to (create window with default profile)
      set s to current session of current tab of w
    else
      tell current window
        set t to (create tab with default profile)
      end tell
      set s to current session of t
    end if
    tell s to write text (item 1 of argv)
    return (id of s) & " " & (tty of s)
  end tell
end run
OSA
) || return 1
  printf '%s\n' "${out/\/dev\//}"
}

be_tabs() { # -> "<tab id> <tty>" for every live session
  iterm_running || return 0
  osascript <<'OSA' | sed 's#/dev/##'
set out to ""
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set out to out & (id of s) & " " & (tty of s) & linefeed
      end repeat
    end repeat
  end repeat
end tell
return out
OSA
}

be_procs() { ps -axo pid=,tty=,command= 2>/dev/null; }          # -> "<pid> <tty> <command>"
be_pid_cmd() { local c; c=$(ps -p "$1" -o command= 2>/dev/null) || return 1; [ -n "$c" ] || return 1; printf '%s\n' "$c"; }
be_pid_tty() { ps -p "$1" -o tty= 2>/dev/null | tr -d ' '; }
be_pid_cwd() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }
be_kill() { kill -TERM "$1"; }
be_mem_free() { memory_pressure -Q 2>/dev/null | awk -F': *' '/free percentage/ { gsub(/%/, "", $2); print $2 }'; }
be_sleep() { sleep "$1"; }
be_uuid() { uuidgen | tr 'A-Z' 'a-z'; }

if [ "${TERM_SH_BACKEND:-real}" = "fake" ]; then
  . "$TERM_SH_DIR/../tests/stubs/term-fake"
fi

# ------------------------------------------------------------------ small helpers

shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

need_helpers() {
  [ "$(cfg terminal_helpers off)" = "on" ] || die 3 "terminal_helpers is not 'on' in .local/config; nothing is opened or typed"
  command -v jq >/dev/null 2>&1 || die 3 "jq is required"
}

pid_alive_as() { # pid_alive_as <pid> <match>: the PID runs and its command line contains <match>
  local c
  [ -n "$1" ] && [ "$1" != "null" ] || return 1
  c=$(be_pid_cmd "$1") || return 1
  case "$c" in *"$2"*) return 0 ;; esac
  return 1
}

pid_kill() { # pid_kill <pid> <match>: TERM one exact PID, only when its command line still matches
  local c
  case "$1" in ''|*[!0-9]*) note "refusing to signal '$1': not a PID"; return 3 ;; esac
  c=$(be_pid_cmd "$1") || { note "PID $1 is already gone"; return 0; }
  case "$c" in
    *"$2"*) be_kill "$1" ;;
    *) note "refusing to signal PID $1: its command line does not match '$2'"; return 3 ;;
  esac
}

wait_pid_gone() { # wait_pid_gone <pid> <match> <seconds>
  local end=$((SECONDS + $3))
  while pid_alive_as "$1" "$2"; do
    [ $SECONDS -ge $end ] && return 1
    be_sleep "$POLL"
  done
  return 0
}

# ------------------------------------------------------------------ registry (.local/registry.json)

reg_unlock() {
  if [ "$LOCK_HELD" = 1 ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; LOCK_HELD=0; fi
}
trap reg_unlock EXIT

reg_lock() { # never steals: a lock left by a crashed run is reported, not removed
  local end=$((SECONDS + LOCK_TIMEOUT))
  mkdir -p "$LOCAL_DIR"
  until mkdir "$LOCK" 2>/dev/null; do
    if [ $SECONDS -ge $end ]; then
      note "registry is locked ($LOCK, holder pid $(cat "$LOCK/pid" 2>/dev/null || echo '?')); remove it by hand only if that process is gone"
      return 1
    fi
    sleep 0.05
  done
  LOCK_HELD=1
  echo $$ > "$LOCK/pid"
}

reg_write() { # reg_write <jq args...>: apply a jq program to the registry; caller holds the lock
  local tmp cur=$REG
  [ -f "$cur" ] || cur=/dev/null
  tmp=$(mktemp "$LOCAL_DIR/registry.json.XXXXXX") || return 1
  if { [ "$cur" = /dev/null ] && echo '[]' || cat "$cur"; } | jq "$@" > "$tmp" 2>/dev/null &&
     jq -e 'type == "array"' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$REG"
  else
    rm -f "$tmp"; return 1
  fi
}

reg_update() { # reg_update <jq args...>: lock, write, unlock
  reg_lock || return 1
  reg_write "$@"; local rc=$?
  reg_unlock
  return $rc
}

reg_read() { # reg_read <jq args...> over the registry (an empty list when absent)
  if [ -f "$REG" ]; then jq "$@" "$REG"; else echo '[]' | jq "$@"; fi
}

reg_set() { # reg_set <session_id> <jq object expression> [jq args...]
  local sid=$1 expr=$2; shift 2
  reg_update --arg sid "$sid" "$@" "map(if .session_id == \$sid then . + ($expr) else . end)"
}

# ------------------------------------------------------------------ reading a screen

nonblank() { grep -v '^[[:space:]]*$'; }
screen_tail() { printf '%s\n' "$1" | nonblank | tail -n "${2:-15}"; }

has_dialog() { screen_tail "$1" 15 | grep -q -e 'Enter to select' -e 'Esc to cancel'; }
has_headsup() { screen_tail "$1" 15 | grep -q '0: Dismiss'; }
is_busy() { screen_tail "$1" 12 | grep -qi 'esc to interrupt'; }
bg_count() { screen_tail "$1" 6 | grep -oE '[0-9]+ (shells?|background tasks?)' | head -1 | awk '{ print $1 + 0 }'; }

box_text() { # box_text <screen> -> input box text with all spaces removed; rc 1 when no box is drawn
  local raw
  raw=$(printf '%s\n' "$1" | LC_ALL=C awk -v R="$RULE" -v P="$PROMPT" '
    { L[NR] = $0 }
    END {
      r1 = 0; r2 = 0
      for (i = NR; i >= 1; i--) { s = L[i]; sub(/^[ \t]+/, "", s)
        if (index(s, R) == 1) { if (!r2) r2 = i; else { r1 = i; break } } }
      if (r1 && r2) { s = L[r1 + 1]; sub(/^[ \t]+/, "", s)
        if (index(s, P) == 1) { out = ""; for (i = r1 + 1; i < r2; i++) out = out L[i]; print out; exit 0 } }
      for (i = NR; i >= 1 && i > NR - 8; i--) { s = L[i]; sub(/^[ \t]+/, "", s)
        if (index(s, P) == 1) { print L[i]; exit 0 } }
      exit 1
    }') || return 1
  printf '%s' "$raw" | LC_ALL=C sed "s/$PROMPT//g; s/$NBSP//g" | tr -d ' \t\r\n'
}

dialog_question() { # dialog_question <screen> -> the question text above the first option
  printf '%s\n' "$1" | LC_ALL=C awk -v R="$RULE" -v P="$PROMPT" '
    function trim(s) { sub(/^[ \t]+/, "", s); if (index(s, P) == 1) s = substr(s, length(P) + 1); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    { L[NR] = $0 }
    END {
      o = 0; for (i = 1; i <= NR; i++) if (trim(L[i]) ~ /^1\.[ \t]/) o = i
      if (!o) exit 1
      st = 1; for (i = o - 1; i >= 1; i--) { s = L[i]; sub(/^[ \t]+/, "", s); if (index(s, R) == 1) { st = i + 1; break } }
      out = ""; for (i = st; i < o; i++) { s = trim(L[i]); if (s != "") out = (out == "" ? s : out " " s) }
      print out
    }'
}

freetext_row() { # freetext_row <screen> -> number of the dialog row that takes free text
  printf '%s\n' "$1" | LC_ALL=C awk -v P="$PROMPT" '
    { s = $0; sub(/^[ \t]+/, "", s); if (index(s, P) == 1) s = substr(s, length(P) + 1); sub(/^[ \t]+/, "", s)
      if (s ~ /^[0-9]+\.[ \t]+(Type something|Other)/) { split(s, a, "."); n = a[1] } }
    END { if (n == "") exit 1; print n }'
}

# ------------------------------------------------------------------ resolving a target (rule 1)

T_TTY=""; T_TAB=""; T_SID=""; T_PID=""; T_MATCH=""; T_ISSUE=""; T_CLOSED=""; T_REG=0; T_ALIVE=0
T_ADOPTED=0; ADOPT_NEW=0; ADOPT_RESUME=""

load_entry() { # load_entry <json object>
  T_SID=$(printf '%s' "$1" | jq -r '.session_id // ""')
  T_TTY=$(printf '%s' "$1" | jq -r '.tty // ""')
  T_TAB=$(printf '%s' "$1" | jq -r '.tab // ""')
  T_PID=$(printf '%s' "$1" | jq -r '.pid // ""')
  T_MATCH=$(printf '%s' "$1" | jq -r '.match // ""')
  T_ISSUE=$(printf '%s' "$1" | jq -r '.issue // ""')
  T_CLOSED=$(printf '%s' "$1" | jq -r '.closed // ""')
  T_ADOPTED=$(printf '%s' "$1" | jq -r 'if .adopted == true then 1 else 0 end')
  T_REG=1
}

resolve() { # resolve <target> [any]: sets T_*; "any" also accepts a closed registry entry
  local target=$1 mode=${2:-open} entry n live
  T_TTY=""; T_TAB=""; T_SID=""; T_PID=""; T_MATCH=""; T_ISSUE=""; T_CLOSED=""; T_REG=0; T_ALIVE=0
  T_ADOPTED=0
  case "$target" in
    /dev/tty*|tty*)
      T_TTY=${target#/dev/}
      case "$T_TTY" in *[!A-Za-z0-9]*) die 2 "not a tty: '$target'" ;; esac
      entry=$(reg_read -c --arg t "$T_TTY" '[.[] | select(.tty == $t and .closed == null)] | last // empty')
      [ -n "$entry" ] && load_entry "$entry" ;;
    *)
      if printf '%s' "$target" | grep -Eq '^[0-9a-fA-F-]{8,}$'; then
        n=$(reg_read --arg s "$target" '[.[] | select(.session_id | startswith($s))] | length')
        [ "$n" = 1 ] || die 4 "session id '$target' matches $n registry entries"
        load_entry "$(reg_read -c --arg s "$target" '.[] | select(.session_id | startswith($s))')"
      else
        die 2 "address a tab by tty or session id, never by title ('$target')"
      fi ;;
  esac
  if [ "$T_REG" = 1 ] && [ -n "$T_CLOSED" ]; then
    [ "$mode" = any ] && return 0
    die 3 "session $T_SID was closed at $T_CLOSED"
  fi
  [ -n "$T_TTY" ] || die 4 "session $T_SID has no tty yet"
  live=$(be_tabs | awk -v t="$T_TTY" '$2 == t && !f { print $1; f = 1 }')
  [ -n "$live" ] || die 4 "no live tab on $T_TTY"
  if [ -n "$T_TAB" ] && [ "$live" != "$T_TAB" ]; then
    die 4 "tab on $T_TTY is $live, not the recorded $T_TAB (tty reused)"
  fi
  T_TAB=$live
  if [ -n "$T_PID" ]; then
    if be_pid_cmd "$T_PID" >/dev/null; then
      if [ "$(be_pid_tty "$T_PID")" != "$T_TTY" ] || ! pid_alive_as "$T_PID" "$T_MATCH"; then
        die 3 "PID $T_PID is not the recorded session on $T_TTY (PID reused); refusing"
      fi
      T_ALIVE=1
    fi
  fi
  return 0
}

# ------------------------------------------------------------------ adopting the owner's own tab (rule 15)

adopt_target() { # adopt_target <target>: after resolve; verify a tab the owner opened by hand
  local name pids n cmd sid cwd
  case "$1" in /dev/tty*|tty*) ;; *) die 2 "--adopt needs an explicit tty, not '$1'" ;; esac
  if [ "$T_REG" = 1 ]; then
    [ "$T_ADOPTED" = 1 ] || die 2 "the tab on $T_TTY is in this home's registry already; drop --adopt"
    return 0
  fi
  name=$(local_cfg launch.command claude); name=${name##*/}
  pids=$(be_procs | awk -v t="$T_TTY" -v c="$name" '$2 == t { n = split($3, p, "/"); if (p[n] == c) print $1 }')
  n=$(printf '%s\n' "$pids" | grep -c .)
  [ "$n" = 0 ] && die 4 "no $name process runs on $T_TTY; nothing to adopt"
  [ "$n" = 1 ] || die 3 "$n $name processes run on $T_TTY; not guessing which one"
  case "$pids" in *[!0-9]*) die 3 "not a PID: '$pids'" ;; esac
  cmd=$(be_pid_cmd "$pids") || die 4 "PID $pids on $T_TTY is gone"
  [ "$(printf '%s\n' "$cmd" | awk '{ n = split($1, p, "/"); print p[n] }')" = "$name" ] ||
    die 3 "PID $pids does not run $name ('$cmd'); refusing"
  [ "$(be_pid_tty "$pids")" = "$T_TTY" ] || die 3 "PID $pids is not on $T_TTY; refusing"
  be_screen "$T_TTY" "$T_TAB" >/dev/null || die 4 "the screen of the tab on $T_TTY cannot be read"
  sid=$(printf '%s\n' "$cmd" | awk '{ for (i = 1; i <= NF; i++) {
      if (($i == "--session-id" || $i == "--resume" || $i == "-r") && i < NF) { print $(i + 1); exit }
      if ($i ~ /^--(session-id|resume)=/) { sub(/^[^=]*=/, "", $i); print $i; exit } } }')
  cwd=$(be_pid_cwd "$pids")
  T_PID=$pids; T_ALIVE=1; T_ADOPTED=1; ADOPT_NEW=1
  if printf '%s' "$sid" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$'; then
    T_SID=$sid; T_MATCH=$sid
    ADOPT_RESUME="cd $(shq "${cwd:-.}") && $(shq "$(printf '%s\n' "$cmd" | awk '{ print $1 }')") --resume $sid"
  else
    T_SID=$(be_uuid); T_MATCH=$cmd   # no session id: the exact command line is the match
  fi
}

adopt_record() { # adopt_record <issue>: add the adopted tab to the registry; nothing is typed before this
  local entry
  [ "$ADOPT_NEW" = 1 ] || return 0
  entry=$(jq -nc --arg sid "$T_SID" --arg tty "$T_TTY" --arg tab "$T_TAB" --arg pid "$T_PID" \
    --arg cwd "$(be_pid_cwd "$T_PID")" --arg issue "$1" --arg resume "$ADOPT_RESUME" --arg opened "$(now_utc)" \
    --arg match "$T_MATCH" \
    '{session_id: $sid, tty: $tty, pid: ($pid | tonumber), cwd: $cwd,
      issue: (if $issue == "" then null else ($issue | tonumber) end),
      resume: (if $resume == "" then null else $resume end), opened: $opened, closed: null,
      role: "owner", tab: $tab, match: $match, adopted: true}') || die 3 "could not build the registry entry; nothing was typed"
  reg_update --argjson e "$entry" '. + [$e]' || die 3 "registry write failed; nothing was typed"
  ADOPT_NEW=0
}

screen_now() { be_screen "$T_TTY" "$T_TAB" || die 4 "tab on $T_TTY is gone"; }
settle() { be_sleep "$SETTLE"; }

# ------------------------------------------------------------------ typing

type_text() { # type_text <text>: in chunks, never a newline
  local rest=$1 chunk
  while [ -n "$rest" ]; do
    chunk=${rest:0:$CHUNK}; rest=${rest:$CHUNK}
    be_type "$T_TTY" "$T_TAB" "$chunk" || die 4 "tab on $T_TTY is gone"
    settle
  done
}

norm() { printf '%s' "$1" | LC_ALL=C sed "s/$NBSP//g" | tr -d ' \t\r\n'; }

ghost_probe() { # ghost_probe <current box>: rc 0 = suggestion (box now empty), rc 1 = real draft (kept)
  local b2 b3
  be_type "$T_TTY" "$T_TAB" "x" || return 1
  settle
  b2=$(box_text "$(screen_now)")
  be_key "$T_TTY" "$T_TAB" bs
  settle
  [ "$b2" = "x" ] && return 0
  b3=$(box_text "$(screen_now)")
  [ "$b3" = "$1" ] || note "box on $T_TTY changed during the probe; leaving it as it is"
  return 1
}

submit() { # submit <text>: type into an empty box, press Enter, re-check once (rule 6)
  local want scr b
  want=$(norm "$1"); want=${want:0:30}
  type_text "$1"
  scr=$(screen_now)
  has_dialog "$scr" && die 3 "a dialog opened while typing on $T_TTY; Enter not pressed"
  b=$(box_text "$scr") || die 3 "the input box on $T_TTY disappeared while typing; Enter not pressed"
  case "$b" in *"$want"*) ;; *) die 5 "the typed text did not reach the box on $T_TTY; Enter not pressed" ;; esac
  be_key "$T_TTY" "$T_TAB" cr; settle
  b=$(box_text "$(be_screen "$T_TTY" "$T_TAB" 2>/dev/null)") || return 0
  case "$b" in *"$want"*) ;; *) return 0 ;; esac
  note "Enter was swallowed on $T_TTY; pressing it once more"
  be_key "$T_TTY" "$T_TAB" cr; settle
  b=$(box_text "$(be_screen "$T_TTY" "$T_TAB" 2>/dev/null)") || return 0
  case "$b" in *"$want"*) die 5 "Enter swallowed twice on $T_TTY; the text is still in the box" ;; esac
  return 0
}

login_dialog_re() { cfg term.login_dialog_re 'log[ -]?in|sign[ -]?in|authenticat|session (has )?expired|re-?auth'; }

login_row() { # login_row <screen> -> free-text row of an open login dialog; rc 1 otherwise
  local q
  has_dialog "$1" || return 1
  q=$(dialog_question "$1") || return 1
  printf '%s\n' "$q" | grep -Eqi -- "$(login_dialog_re)" || return 1
  freetext_row "$1"
}

dialog_row() { # dialog_row <screen> -> free-text row of any open dialog; rc 1 otherwise
  has_dialog "$1" || return 1
  freetext_row "$1"
}

count_in() { # count_in <haystack> <needle> -> how often the needle occurs
  TS_HAY=$1 TS_NEEDLE=$2 LC_ALL=C awk 'BEGIN { h = ENVIRON["TS_HAY"]; n = ENVIRON["TS_NEEDLE"]; c = 0
    if (n != "") while ((i = index(h, n)) > 0) { c++; h = substr(h, i + length(n)) }
    print c }'
}

answer_freetext() { # answer_freetext <row fn> <row> <text>: type into the free-text row (rules 7 and 16)
  local scr row want before
  scr=$(screen_now)   # read again right before typing: the dialog may have changed or closed
  row=$("$1" "$scr") || return 1
  [ "$row" = "$2" ] || return 1
  be_type "$T_TTY" "$T_TAB" "$row"; settle
  scr=$(screen_now)
  has_dialog "$scr" || die 3 "the dialog on $T_TTY closed before the answer was typed"
  want=$(norm "$3")
  before=$(count_in "$(norm "$scr")" "$want")
  type_text "$3"
  scr=$(screen_now)
  has_dialog "$scr" || die 3 "the dialog on $T_TTY closed while the answer was typed; Enter not pressed"
  [ "$(count_in "$(norm "$scr")" "$want")" -gt "$before" ] ||
    die 3 "the answer did not appear in the free-text row on $T_TTY; Enter not pressed"
  be_key "$T_TTY" "$T_TAB" cr; settle
}

trivial_check() { # trivial_check <command>: rc 0 when the check proves nothing (rule 7)
  local c
  c=$(printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/^ *//; s/ *$//; s/  */ /g')
  case "$c" in ''|true|:|'exit 0'|echo|'echo '*|'test 1') return 0 ;; esac
  return 1
}

dismiss_headsup() { # one "0" press; if the notice stays, take the 0 back and report
  local scr b
  be_type "$T_TTY" "$T_TAB" "0" || return 1
  settle
  scr=$(screen_now)
  has_headsup "$scr" || return 0
  b=$(box_text "$scr") && [ "$b" = 0 ] && { be_key "$T_TTY" "$T_TAB" bs; settle; }
  return 1
}

wait_quiet() { # wait_quiet <seconds>: until no dialog, no running turn and an empty box
  local end=$((SECONDS + $1)) scr b
  while [ $SECONDS -lt $end ]; do
    scr=$(screen_now)
    if ! has_dialog "$scr" && ! is_busy "$scr"; then
      b=$(box_text "$scr") && [ -z "$b" ] && return 0
    fi
    be_sleep "$POLL"
  done
  return 1
}

exit_shell() { # after the session's process is gone: leave the plain shell so the tab closes
  local scr
  scr=$(be_screen "$T_TTY" "$T_TAB" 2>/dev/null) || return 0
  if has_dialog "$scr" || box_text "$scr" >/dev/null || claude_on_tty "$T_TTY"; then
    note "something still runs in the tab on $T_TTY; the shell is left open"
    return 0
  fi
  be_type "$T_TTY" "$T_TAB" "exit" || return 0
  be_key "$T_TTY" "$T_TAB" cr || return 0
}

claude_on_tty() { # claude_on_tty <tty>: a claude process runs on that tty
  be_procs | awk -v t="$1" '$2 == t { n = split($3, p, "/"); if (p[n] == "claude") f = 1 } END { exit !f }'
}

exit_session() { # exit_session <exit word> <seconds>: type it, verify the PID is gone; never force
  submit "$1"
  wait_pid_gone "$T_PID" "$T_MATCH" "$2" ||
    die 5 "PID $T_PID is still alive after '$1'; nothing was force-closed, the tab is left as it is"
}

# ------------------------------------------------------------------ launching (rules 11 and 14)

local_cfg() { # local_cfg <key> [default]: from .local/config only (rule 14)
  local v
  v=$(cfg_read_file "$LOCAL_DIR/config" "$1") || v=${2:-}
  printf '%s\n' "$v"
}

launch_prefix() { # launch_prefix <role> -> "<command> [<profile flag> P] [--model M]"
  local cmd flag prof model line
  cmd=$(local_cfg launch.command claude)
  flag=$(local_cfg launch.profile_flag)
  prof=$(local_cfg "launch.profile.$1")
  model=$(local_cfg launch.model)
  printf '%s' "$cmd" | grep -Eq '^[A-Za-z0-9_./-]+$' ||
    die 3 "launch.command must be one command word, not '$cmd'"
  [ -z "$flag" ] || printf '%s' "$flag" | grep -Eq '^--?[A-Za-z0-9][A-Za-z0-9-]*$' ||
    die 3 "launch.profile_flag must be one flag such as -p, not '$flag'"
  if [ -n "$model" ] && ! printf '%s' "$model" | grep -Eq '^[a-z]+(\[1m\])?$'; then
    die 3 "launch.model must be an alias (opus, sonnet, ...), not '$model'"
  fi
  line=$cmd
  [ -n "$flag" ] && [ -n "$prof" ] && line="$line $flag $(shq "$prof")"
  [ -n "$model" ] && line="$line --model $(shq "$model")"
  printf '%s\n' "$line"
}

check_memory() {
  local min free
  min=$(cfg term.min_free_pct 20)
  case "$min" in ''|*[!0-9]*) die 3 "term.min_free_pct must be a whole number, not '$min'" ;; esac
  [ "$min" = 0 ] && return 0
  free=$(be_mem_free)
  case "$free" in ''|*[!0-9]*) die 3 "memory pressure cannot be read; not opening a tab (set term.min_free_pct=0 to skip the check)" ;; esac
  [ "$free" -lt "$min" ] && die 3 "memory pressure is high (${free}% free, minimum ${min}%); not opening a tab"
  return 0
}

count_live_workers() { # caller holds the lock
  local n=0 pid match
  while read -r pid match; do
    [ -n "$pid" ] || continue
    if [ "$pid" = null ] || pid_alive_as "$pid" "$match"; then n=$((n + 1)); fi
  done <<EOF
$(reg_read -r --argjson w "$((OPEN_WAIT + 60))" '.[] | select(.closed == null and (.role // "worker") == "worker")
  | if .pid == null then (if ((.opened | fromdateiso8601) > (now - $w)) then "null -" else empty end)
    else "\(.pid) \(.match)" end')
EOF
  echo "$n"
}

reserve() { # reserve <json entry> <role>: add the entry unless the worker cap is reached
  local cap n
  cap=$(cfg term.max_workers 4)
  reg_lock || die 3 "could not lock the registry"
  if [ "$2" = worker ]; then
    n=$(count_live_workers)
    if [ "$n" -ge "$cap" ]; then reg_unlock; die 3 "worker cap reached ($n of $cap open); not opening a tab"; fi
  fi
  reg_write --argjson e "$1" '. + [$e]' || { reg_unlock; die 3 "registry write failed"; }
  reg_unlock
}

find_pid() { # find_pid <tty> <match> -> newest PID on that tty whose command line holds <match>
  local end=$((SECONDS + OPEN_WAIT)) pid
  while :; do
    pid=$(be_procs | awk -v t="$1" -v m="$2" '$2 == t && index($0, m) > 0 { print $1 }' | sort -n | tail -1)
    [ -n "$pid" ] && { echo "$pid"; return 0; }
    [ $SECONDS -ge $end ] && return 1
    be_sleep "$POLL"
  done
}

launch_tab() { # launch_tab <sid> <command line> <match>: open, record tty/tab/pid, print the triple
  local sid=$1 out tab tty pid
  out=$(be_open "$2") || { reg_set "$sid" '{closed: $c}' --arg c "$(now_utc)"; die 4 "could not open a tab"; }
  tab=${out%% *}; tty=${out#* }
  reg_set "$sid" '{tab: $tab, tty: $tty}' --arg tab "$tab" --arg tty "$tty" ||
    die 3 "tab $tty opened but the registry could not be updated; close it by hand"
  pid=$(find_pid "$tty" "$3") || {
    reg_set "$sid" '{closed: $c}' --arg c "$(now_utc)"
    die 5 "tab $tty opened but no process matching the launch appeared; marked closed"
  }
  reg_set "$sid" '{pid: ($p | tonumber)}' --arg p "$pid" ||
    die 3 "tab $tty (PID $pid) opened but the registry could not be updated"
  echo "$sid $tty $pid"
}

# ------------------------------------------------------------------ verbs

cmd_open() {
  local dir="" issue="" role=worker brief="" brief_file="" sid prefix line resume match entry
  [ $# -ge 1 ] || die 2 "usage: open <dir> [--issue N] [--role worker|orchestrator] [--brief T|--brief-file F]"
  dir=$1; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue=${2:-}; shift 2 ;;
      --role) role=${2:-}; shift 2 ;;
      --brief) brief=${2:-}; shift 2 ;;
      --brief-file) brief_file=${2:-}; shift 2 ;;
      *) die 2 "open: unknown option '$1'" ;;
    esac
  done
  need_helpers
  case "$role" in worker|orchestrator) ;; *) die 2 "role must be worker or orchestrator" ;; esac
  case "$issue" in *[!0-9]*) die 2 "issue must be a number" ;; esac
  case "$brief" in *"
"*) die 2 "the brief must be one line; use --brief-file for more" ;; esac
  [ -z "$brief_file" ] || [ -f "$brief_file" ] || die 2 "no brief file '$brief_file'"
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || die 2 "no such directory"
  prefix=$(launch_prefix "$role") || exit $?
  check_memory
  sid=$(be_uuid)
  resume="cd $(shq "$dir") && $prefix --resume $sid"
  line="cd $(shq "$dir") && $prefix --session-id $sid"
  [ -n "$brief" ] && line="$line $(shq "$brief")"
  [ -n "$brief_file" ] && line="$line \"\$(cat $(shq "$(cd "$(dirname "$brief_file")" && pwd -P)/$(basename "$brief_file")"))\""
  match=$sid
  entry=$(jq -nc --arg sid "$sid" --arg cwd "$dir" --arg issue "$issue" --arg resume "$resume" \
    --arg opened "$(now_utc)" --arg role "$role" --arg match "$match" \
    '{session_id: $sid, tty: null, pid: null, cwd: $cwd, issue: (if $issue == "" then null else ($issue | tonumber) end),
      resume: $resume, opened: $opened, closed: null, role: $role, tab: null, match: $match}')
  reserve "$entry" "$role"
  launch_tab "$sid" "$line" "$match"
}

cmd_screen() {
  local target lines=0 scr
  [ $# -ge 1 ] || die 2 "usage: screen <target> [--lines N]"
  target=$1; shift
  [ "${1:-}" = --lines ] && lines=${2:-0}
  need_helpers; resolve "$target"
  scr=$(screen_now | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')
  if [ "$lines" -gt 0 ] 2>/dev/null; then printf '%s\n' "$scr" | tail -n "$lines"; else printf '%s\n' "$scr"; fi
}

state_of() { # state_of <screen>
  local b n
  if has_dialog "$1"; then echo dialog; return; fi
  if has_headsup "$1"; then echo headsup; return; fi
  if is_busy "$1"; then echo busy; return; fi
  b=$(box_text "$1") || { echo shell; return; }
  n=$(bg_count "$1")
  if [ -n "$n" ] && [ "$n" -gt 0 ]; then echo bg; return; fi
  if [ -n "$b" ]; then echo draft; else echo idle; fi
}

cmd_state() {
  [ $# -ge 1 ] || die 2 "usage: state <target>"
  need_helpers; resolve "$1"
  if [ -n "$T_PID" ] && [ "$T_ALIVE" = 0 ]; then echo gone; return 0; fi
  state_of "$(screen_now)"
}

cmd_send() {
  local target text after="" after_set=0 timeout=600 end scr b row draft="" after_ok=0
  [ $# -ge 2 ] || die 2 "usage: send <target> <text> [--after CMD] [--timeout S] | send <target> --relay WORDS | send <target> --cancel-dialog"
  target=$1; shift
  case "$1" in
    --relay)
      [ $# -eq 2 ] || die 2 "usage: send <target> --relay \"<the owner's own words>\" (no other option)"
      send_relay "$target" "$2"; return ;;
    --cancel-dialog)
      [ $# -eq 1 ] || die 2 "usage: send <target> --cancel-dialog (no other option)"
      send_cancel "$target"; return ;;
  esac
  text=$1; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --after) after=${2:-}; after_set=1; shift 2 ;;
      --timeout) timeout=${2:-}; shift 2 ;;
      *) die 2 "send: unknown option '$1'" ;;
    esac
  done
  one_line "$text"
  if [ "$after_set" = 1 ] && trivial_check "$after"; then
    die 3 "--after '$after' proves nothing; the check must prove the login, e.g. a CLI identity call"
  fi
  need_helpers; resolve "$target"
  [ -z "$after" ] && after_ok=1
  end=$((SECONDS + timeout))
  while [ $SECONDS -lt $end ]; do
    if [ "$after_ok" = 0 ]; then
      if /bin/bash -c "$after" >/dev/null 2>&1; then after_ok=1; else be_sleep "$POLL"; continue; fi
    fi
    scr=$(screen_now)   # read after the check, never before it
    if has_dialog "$scr"; then
      if [ -n "$after" ] && row=$(login_row "$scr") && answer_freetext login_row "$row" "$text"; then
        echo "ANSWERED $T_TTY (login dialog, free-text row $row, after the check passed)"
        return 0
      fi
      be_sleep "$POLL"; continue
    fi
    if has_headsup "$scr"; then
      dismiss_headsup || die 3 "the notice on $T_TTY did not go away after one dismiss; nothing sent"
      continue
    fi
    if is_busy "$scr"; then be_sleep "$POLL"; continue; fi
    if ! b=$(box_text "$scr"); then be_sleep "$POLL"; continue; fi
    if [ -z "$b" ]; then submit "$text"; echo "SENT $T_TTY"; return 0; fi
    if [ "$b" != "$draft" ]; then
      if ghost_probe "$b"; then submit "$text"; echo "SENT $T_TTY (cleared a suggestion)"; return 0; fi
      draft=$b
      note "a real draft is in the box on $T_TTY; waiting, it is never cleared"
    fi
    be_sleep "$POLL"
  done
  die 5 "timed out on $T_TTY; nothing was sent"
}

one_line() { # one_line <text>: refuse empty or multi-line text
  [ -n "$1" ] || die 2 "empty text"
  case "$1" in *"
"*|*$'\r'*) die 2 "text must be one line (put long content in a file and send its path)" ;; esac
}

send_relay() { # send_relay <target> <words>: the owner's own words into an open dialog's free-text row (rule 16)
  local scr row
  one_line "$2"
  need_helpers; resolve "$1"
  scr=$(screen_now)
  has_dialog "$scr" || die 3 "no dialog is open on $T_TTY; nothing relayed"
  row=$(freetext_row "$scr") || die 3 "the dialog on $T_TTY has no free-text row; nothing relayed (a listed option is never picked)"
  answer_freetext dialog_row "$row" "$2" || die 3 "the free-text row of the dialog on $T_TTY changed; nothing relayed"
  echo "RELAYED $T_TTY (free-text row $row)"
}

send_cancel() { # send_cancel <target>: one Esc on an open dialog, then check it closed (rule 17)
  need_helpers; resolve "$1"
  has_dialog "$(screen_now)" || die 3 "no dialog is open on $T_TTY; nothing pressed"
  be_key "$T_TTY" "$T_TAB" esc || die 4 "tab on $T_TTY is gone"
  settle
  has_dialog "$(screen_now)" && die 5 "the dialog on $T_TTY is still open after one Esc; not pressed again"
  echo "CANCELLED $T_TTY"
}

issue_finished() { # issue_finished <repo> <n>: a final home-log comment exists and no owner label (rule 8)
  local repo=$1 n=$2 raw comments labels owner
  raw=$(gh api --paginate "repos/$repo/issues/$n/comments?per_page=100" 2>/dev/null) &&
    comments=$(printf '%s' "$raw" | jq -s 'add // []' 2>/dev/null) ||
    die 3 "cannot read the comments of $repo#$n; not closing"
  printf '%s' "$comments" | jq -e 'any(.[]; .body | test("^<!-- home-log run=[^ ]+ state=final -->"))' >/dev/null ||
    die 3 "issue $repo#$n has no final home-log comment; not closing"
  labels=$(gh api "repos/$repo/issues/$n" --jq '.labels[].name' 2>/dev/null) ||
    die 3 "cannot read the labels of $repo#$n; not closing"
  owner=$(cfg labels.needs_owner needs-owner)
  printf '%s\n' "$labels" | grep -qxF -- "$owner" &&
    die 3 "issue $repo#$n carries '$owner' (a question waits on the owner); not closing"
  return 0
}

pick_issue() { # pick_issue <given>: the registry issue unless the caller passed a different one
  if [ -n "$1" ] && [ -n "$T_ISSUE" ] && [ "$1" != "$T_ISSUE" ]; then
    die 3 "session $T_SID belongs to issue #$T_ISSUE, not #$1"
  fi
  if [ -n "$1" ]; then echo "$1"; else echo "$T_ISSUE"; fi
}

exit_word() { if [ "$T_MATCH" = "$T_SID" ] || [ "$T_ADOPTED" = 1 ]; then echo /exit; else echo exit; fi; }

cmd_close() {
  local target issue="" repo=$HOME_REPO timeout=$EXIT_WAIT scr b n adopt=0
  [ $# -ge 1 ] || die 2 "usage: close <target> [--issue N] [--adopt] [--repo OWNER/REPO] [--timeout S]"
  target=$1; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue=${2:-}; shift 2 ;;
      --adopt) adopt=1; shift ;;
      --repo) repo=${2:-}; shift 2 ;;
      --timeout) timeout=${2:-}; shift 2 ;;
      *) die 2 "close: unknown option '$1'" ;;
    esac
  done
  case "$issue" in *[!0-9]*) die 2 "issue must be a number" ;; esac
  printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ||
    die 2 "close needs the repo as OWNER/REPO (--repo, or repo in home.config)"
  need_helpers; resolve "$target"
  [ "$adopt" = 1 ] && adopt_target "$target"
  [ "$T_REG" = 1 ] || [ "$ADOPT_NEW" = 1 ] ||
    die 3 "close works only on tabs this home opened (none recorded on $T_TTY; the owner's own tab needs --adopt)"
  issue=$(pick_issue "$issue") || exit $?
  if [ -n "$issue" ]; then
    issue_finished "$repo" "$issue"
  elif [ "$adopt" = 0 ] || [ "$T_ADOPTED" = 0 ]; then
    die 2 "close needs the issue number (--issue N, or one recorded at open)"
  fi
  if [ "$T_ALIVE" = 1 ]; then
    scr=$(screen_now)
    if has_headsup "$scr"; then
      adopt_record "$issue"
      dismiss_headsup || die 3 "the notice on $T_TTY did not go away; not closing"
      scr=$(screen_now)
    fi
    has_dialog "$scr" && die 3 "a question is open on $T_TTY; not closing"
    is_busy "$scr" && die 3 "a turn is running on $T_TTY; not closing"
    n=$(bg_count "$scr")
    [ -n "$n" ] && [ "$n" -gt 0 ] && die 3 "$n background job(s) on $T_TTY; not closing"
    if [ "$(exit_word)" = /exit ]; then
      b=$(box_text "$scr") || die 3 "no input box on $T_TTY; not closing"
      if [ -n "$b" ]; then adopt_record "$issue"; ghost_probe "$b" || die 3 "an unsent draft is in the box on $T_TTY; not closing"; fi
    fi
    adopt_record "$issue"
    exit_session "$(exit_word)" "$timeout"
  fi
  exit_shell
  reg_set "$T_SID" '{closed: $c}' --arg c "$(now_utc)" || note "registry not updated"
  echo "CLOSED $T_SID $T_TTY"
}

cmd_park() {
  local target issue="" timeout=$EXIT_WAIT scr b q="" text dialog=0 adopt=0
  [ $# -ge 1 ] || die 2 "usage: park <target> [--issue N] [--adopt] [--timeout S]"
  target=$1; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue=${2:-}; shift 2 ;;
      --adopt) adopt=1; shift ;;
      --timeout) timeout=${2:-}; shift 2 ;;
      *) die 2 "park: unknown option '$1'" ;;
    esac
  done
  need_helpers; resolve "$target"
  [ "$adopt" = 1 ] && adopt_target "$target"
  [ "$T_REG" = 1 ] || [ "$ADOPT_NEW" = 1 ] || die 3 "park works only on tabs this home opened (the owner's own tab needs --adopt)"
  [ "$T_MATCH" = "$T_SID" ] || die 3 "park needs a session launched with a session id"
  [ "$T_ALIVE" = 1 ] || die 4 "session $T_SID is not running"
  issue=$(pick_issue "$issue") || exit $?
  [ -n "$issue" ] || die 2 "park needs the issue number"
  scr=$(screen_now)
  if has_headsup "$scr"; then
    adopt_record "$issue"
    dismiss_headsup || die 3 "the notice on $T_TTY did not go away; not parking"
    scr=$(screen_now)
  fi
  if has_dialog "$scr"; then
    dialog=1
    q=$(dialog_question "$scr") || q="(open question on screen; see the session)"
  else
    is_busy "$scr" && die 3 "session is busy; park it when idle"
    b=$(box_text "$scr") || die 3 "no input box on $T_TTY; not parking"
    if [ -n "$b" ]; then adopt_record "$issue"; ghost_probe "$b" || die 3 "an unsent draft is in the box on $T_TTY; not parking"; fi
  fi
  adopt_record "$issue"
  text="Parked by term.sh. Resume: $(reg_read -r --arg s "$T_SID" '.[] | select(.session_id == $s) | .resume')"
  if [ -n "$q" ]; then
    "$HOME_LOG" checkpoint "$issue" --run-id "$T_SID" --park --question "$q" --text "$text" >/dev/null ||
      die 3 "home-log failed; the session is left running"
  else
    "$HOME_LOG" checkpoint "$issue" --run-id "$T_SID" --park --text "$text" >/dev/null ||
      die 3 "home-log failed; the session is left running"
  fi
  if [ "$dialog" = 1 ]; then
    be_key "$T_TTY" "$T_TAB" esc; settle   # Esc cancels the dialog; it never answers it
    wait_quiet "$timeout" || die 5 "the session on $T_TTY did not settle after the dialog was cancelled"
  fi
  exit_session /exit "$timeout"
  exit_shell
  reg_set "$T_SID" '{closed: $c, parked: true}' --arg c "$(now_utc)" || note "registry not updated"
  echo "PARKED $T_SID issue #$issue"
}

run_has_question() { # run_has_question <repo> <n> <run id>: 0 when the run's last home-log comment holds an open owner question
  local raw
  raw=$(gh api --paginate "repos/$1/issues/$2/comments?per_page=100" 2>/dev/null) || return 2
  printf '%s' "$raw" | jq -s -e --arg r "$3" '
    [(add // [])[] | .body | select(startswith("<!-- home-log run=" + $r + " "))] | last // "" |
    test("(^|\n)- Open question for the owner: ")' >/dev/null
}

cmd_resume() {
  local sid line role issue msg="" silent=0 nopt=0
  [ $# -ge 1 ] || die 2 "usage: resume <session_id> [--message TEXT | --silent]"
  sid=$1; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --message) [ $# -ge 2 ] && [ -n "$2" ] || die 2 "resume: --message needs a text"; msg=$2; nopt=$((nopt + 1)); shift 2 ;;
      --silent) silent=1; nopt=$((nopt + 1)); shift ;;
      --timeout) shift 2 ;;   # accepted for older callers; resume does not wait
      *) die 2 "resume: unknown option '$1'" ;;
    esac
  done
  [ "$nopt" -le 1 ] || die 2 "resume: use one of --message or --silent"
  need_helpers
  resolve "$sid" any
  [ "$T_REG" = 1 ] || die 4 "no registry entry for '$sid'"
  [ -n "$T_CLOSED" ] || die 3 "session $T_SID is still open on $T_TTY"
  [ "$T_MATCH" = "$T_SID" ] || die 3 "session $T_SID was not a resumable session"
  sid=$T_SID
  role=$(reg_read -r --arg s "$sid" '.[] | select(.session_id == $s) | .role // "worker"')
  line=$(reg_read -r --arg s "$sid" '.[] | select(.session_id == $s) | .resume')
  [ -n "$line" ] || die 3 "no resume command recorded for $sid"
  check_memory
  if [ "$silent" = 0 ] && [ -z "$msg" ]; then
    issue=$T_ISSUE; msg="You were resumed. Continue where you stopped."
    if [ -n "$issue" ] && [ -n "$HOME_REPO" ]; then
      run_has_question "$HOME_REPO" "$issue" "$sid"
      case $? in
        0) msg="You were parked and are resumed now. Re-ask your open question with the ask tool, then continue." ;;
        2) note "cannot read issue #$issue; sending the continue message" ;;
      esac
    fi
  fi
  [ "$silent" = 1 ] || line="$line $(shq "$msg")"
  reg_lock || die 3 "could not lock the registry"
  if [ "$role" = worker ] && [ "$(count_live_workers)" -ge "$(cfg term.max_workers 4)" ]; then
    reg_unlock; die 3 "worker cap reached; not resuming"
  fi
  reg_write --arg s "$sid" --arg o "$(now_utc)" \
    'map(if .session_id == $s then . + {closed: null, parked: false, opened: $o, pid: null, tty: null, tab: null} else . end)' ||
    { reg_unlock; die 3 "registry write failed"; }
  reg_unlock
  launch_tab "$sid" "$line" "$sid"
}

cmd_survey() {
  local want="" tab tty pid kind sid cwd procs found=0
  if [ "${1:-}" = --cwd ]; then want=$(cd "${2:-}" 2>/dev/null && pwd -P) || die 2 "no such directory"; fi
  need_helpers
  procs=$(be_procs)
  while read -r tab tty; do
    [ -n "$tty" ] || continue
    pid=$(printf '%s\n' "$procs" | awk -v t="$tty" '$2 == t { c = $3; n = split(c, p, "/"); if (p[n] == "claude") { print $1; exit } }')
    if [ -n "$pid" ]; then kind=claude
    else
      kind=shell
      pid=$(printf '%s\n' "$procs" | awk -v t="$tty" '$2 == t { print $1 }' | sort -n | tail -1)
    fi
    cwd=""; [ -n "$pid" ] && cwd=$(be_pid_cwd "$pid")
    sid=$(reg_read -r --arg t "$tty" '[.[] | select(.tty == $t and .closed == null)] | last | .session_id // "-"')
    [ "$kind" = shell ] && pid=-
    if [ -n "$want" ]; then
      [ "$kind" = claude ] && [ "$cwd" = "$want" ] || continue
    fi
    found=1
    echo "$tty ${pid:--} $kind $sid ${cwd:--}"
  done <<EOF
$(be_tabs)
EOF
  [ -z "$want" ] || [ "$found" = 1 ]
}

# Sourcing with TERM_SH_LIB=1 loads the functions only (used by the tests).
if [ "${TERM_SH_LIB:-0}" = 1 ]; then return 0 2>/dev/null || exit 0; fi

VERB=${1:-}
[ -n "$VERB" ] && shift
case "$VERB" in
  open) cmd_open "$@" ;;
  screen) cmd_screen "$@" ;;
  state) cmd_state "$@" ;;
  send) cmd_send "$@" ;;
  park) cmd_park "$@" ;;
  resume) cmd_resume "$@" ;;
  close) cmd_close "$@" ;;
  survey) cmd_survey "$@" ;;
  *) die 2 "usage: term.sh open|screen|state|send|park|resume|close|survey ... (see the header of this script)" ;;
esac
