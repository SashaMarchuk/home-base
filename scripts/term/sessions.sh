# shellcheck shell=bash
# sessions.sh: session identity, groups and windows for scripts/term/term.sh. Sourced by term.sh only.
#
# Identity: Claude Code writes <sessions dir>/<pid>.json (pid, sessionId, cwd, name, status) for each
# live session. term.sessions_dirs (comma-separated globs, default ${CLAUDE_CONFIG_DIR:-~/.claude}/sessions)
# says where; the profile is the name of the folder above "sessions" (none when it is .claude).
# The session id comes from the registry (a tab this home opened), then the session file, then the
# command line. A session with no id gets no resume line ("resume: manual") and is never closed by freeze.
#
# The calling session (the one running this script) is found by two signals: the first claude process
# above this script's own process, and CLAUDE_CODE_SESSION_ID matched against the session files.

US=$'\x1f'   # field separator that keeps empty fields

is_uuid() { printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; }
first_base() { printf '%s\n' "$1" | awk '{ n = split($1, p, "/"); print p[n] }'; }
launch_name() { local c; c=$(local_cfg launch.command claude); printf '%s\n' "${c##*/}"; }

session_globs() { # one glob per line from term.sessions_dirs, "~/" expanded
  local v d
  v=$(cfg term.sessions_dirs "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions")
  printf '%s\n' "$v" | tr ',' '\n' | while IFS= read -r d; do
    d=$(printf '%s' "$d" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$d" ] || continue
    case "$d" in "~/"*) d="$HOME/${d#\~/}" ;; esac
    printf '%s\n' "$d"
  done
}

glob_dirs() { # glob_dirs <glob>: the folders it matches (spaces in the path are kept)
  local IFS='' d
  for d in $1; do [ -d "$d" ] && printf '%s\n' "$d"; done
  return 0
}

session_dirs() { local g; session_globs | while IFS= read -r g; do glob_dirs "$g"; done; }

session_of_pid() { # session_of_pid <pid> -> "sid US status US cwd US name US profile US profile dir"; rc 1 when none
  local d f out pdir prof
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    f="$d/$1.json"
    [ -f "$f" ] || continue
    out=$(jq -r --arg p "$1" 'select((.pid | tostring) == $p)
      | [(.sessionId // ""), (.status // ""), (.cwd // ""), (.name // "")] | join("\u001f")' "$f" 2>/dev/null) || continue
    [ -n "$out" ] || continue
    pdir=$(dirname "$d"); prof=${pdir##*/}
    [ "$prof" = .claude ] && prof=""
    printf '%s%s%s%s%s\n' "$out" "$US" "$prof" "$US" "$pdir"
    return 0
  done <<EOF
$(session_dirs)
EOF
  return 1
}

cmdline_sid() { # cmdline_sid <command line> -> the id after --session-id, --resume or -r
  printf '%s\n' "$1" | awk '{ for (i = 1; i <= NF; i++) {
      if (($i == "--session-id" || $i == "--resume" || $i == "-r") && i < NF) { print $(i + 1); exit }
      if ($i ~ /^--(session-id|resume)=/) { sub(/^[^=]*=/, "", $i); print $i; exit } } }'
}

cmdline_opt() { # cmdline_opt <command line> <flag> -> the value of that flag ("--flag v" or "--flag=v")
  local want=$2
  [ -n "$want" ] || return 0
  set -f; set -- $1; set +f
  while [ $# -gt 0 ]; do
    if [ "$1" = "$want" ] && [ $# -gt 1 ]; then printf '%s\n' "$2"; return 0; fi
    case "$1" in "$want="*) printf '%s\n' "${1#*=}"; return 0 ;; esac
    shift
  done
}

resume_line() { # resume_line <cwd> <command line> <profile> <session id> [role] -> the line; rc 1 = resume: manual
  # Kept: launch.command, the profile flag with the profile (session file, else the command line, else
  # launch.profile.<role>), --model <alias> (command line, else launch.model), --dangerously-skip-permissions
  # when the original had it, then --resume <id>. Everything else (prompt, --add-dir, MCP flags) is dropped.
  local cwd=$1 cmd=$2 prof=$3 sid=$4 role=${5:-} flag lcmd model line from_role=0
  is_uuid "$sid" || return 1
  lcmd=$(local_cfg launch.command claude)
  flag=$(local_cfg launch.profile_flag)
  [ -n "$prof" ] || prof=$(cmdline_opt "$cmd" "$flag")
  if [ -z "$prof" ] && [ -n "$role" ]; then prof=$(local_cfg "launch.profile.$role"); from_role=1; fi
  if [ -n "$prof" ] && [ -z "$flag" ]; then
    [ "$from_role" = 1 ] && prof="" || return 1   # a known profile that cannot be passed: never guess
  fi
  model=$(cmdline_opt "$cmd" --model)
  printf '%s' "$model" | grep -Eq '^[a-z]+(\[1m\])?$' || model=$(local_cfg launch.model)
  printf '%s' "$model" | grep -Eq '^[a-z]+(\[1m\])?$' || model=""
  line="cd $(shq "${cwd:-.}") && $(shq "$lcmd")"
  [ -n "$prof" ] && line="$line $flag $(shq "$prof")"
  [ -n "$model" ] && line="$line --model $(shq "$model")"
  case " $cmd " in *" --dangerously-skip-permissions "*) line="$line --dangerously-skip-permissions" ;; esac
  printf '%s --resume %s\n' "$line" "$sid"
}

# ------------------------------------------------------------------ the calling session

CALLER_TTYS=""; IN_SESSION=0

find_caller() { # sets CALLER_TTYS (ttys found by either signal) and IN_SESSION
  local pid n=0 cmd name tty d f p
  CALLER_TTYS=""; IN_SESSION=0
  name=$(launch_name)
  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && IN_SESSION=1
  pid=$(be_self_pid)
  while [ $n -lt 64 ]; do   # signal 1: the first claude process above this one
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
    cmd=$(be_pid_cmd "$pid") || break
    if [ "$(first_base "$cmd")" = "$name" ]; then
      IN_SESSION=1
      tty=$(be_pid_tty "$pid"); [ -n "$tty" ] && CALLER_TTYS="$CALLER_TTYS $tty"
      break
    fi
    pid=$(be_pid_ppid "$pid"); n=$((n + 1))
  done
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then   # signal 2: the session id named by the environment
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      for f in "$d"/*.json; do
        [ -f "$f" ] || continue
        p=$(jq -r --arg s "$CLAUDE_CODE_SESSION_ID" 'select(.sessionId == $s) | .pid // empty' "$f" 2>/dev/null)
        case "$p" in ''|*[!0-9]*) continue ;; esac
        cmd=$(be_pid_cmd "$p") || continue
        [ "$(first_base "$cmd")" = "$name" ] || continue
        tty=$(be_pid_tty "$p"); [ -n "$tty" ] && CALLER_TTYS="$CALLER_TTYS $tty"
      done
    done <<EOF
$(session_dirs)
EOF
  fi
  return 0
}

is_caller() { case " $CALLER_TTYS " in *" $1 "*) return 0 ;; esac; return 1; }

# ------------------------------------------------------------------ survey --json

tab_json() { # tab_json <tab id> <tty> <window> <procs>: one JSON object for a live tab
  local tab=$1 tty=$2 win=$3 procs=$4 name pids n=0 pid="" kind=shell cmd="" cwd="" sid="" src=none
  local sf="" status="" prof="" pdir="" sname="" entry="" reg=false issue="" role="" adopted=false resume="" caller=false
  name=$(launch_name)
  pids=$(printf '%s\n' "$procs" | awk -v t="$tty" -v c="$name" '$2 == t { n = split($3, p, "/"); if (p[n] == c) print $1 }')
  n=$(printf '%s\n' "$pids" | grep -c .)
  if [ "$n" -ge 1 ]; then
    kind=claude; pid=$(printf '%s\n' "$pids" | head -1)
  elif printf '%s\n' "$procs" | awk -v t="$tty" '$2 == t { n = split($3, p, "/"); if (p[n] == "codex") f = 1 } END { exit !f }'; then
    kind=codex
  fi
  if [ "$kind" = claude ] && [ "$n" = 1 ]; then
    cmd=$(be_pid_cmd "$pid" | head -1)
    cwd=$(be_pid_cwd "$pid")
    entry=$(reg_read -c --arg t "$tty" --arg tab "$tab" '[.[] | select(.tty == $t and .closed == null and (.tab == null or .tab == $tab))] | last // empty')
    if [ -n "$entry" ]; then
      reg=true
      issue=$(printf '%s' "$entry" | jq -r '.issue // ""')
      role=$(printf '%s' "$entry" | jq -r '.role // "worker"')
      printf '%s' "$entry" | jq -e '.adopted == true' >/dev/null && adopted=true
      if printf '%s' "$entry" | jq -e '.match == .session_id' >/dev/null; then
        sid=$(printf '%s' "$entry" | jq -r '.session_id'); src=registry
        resume=$(printf '%s' "$entry" | jq -r '.resume // ""')
      fi
    fi
    if sf=$(session_of_pid "$pid"); then
      IFS=$US read -r s_sid status s_cwd sname prof pdir <<EOF
$sf
EOF
      if [ -z "$sid" ] && is_uuid "$s_sid"; then sid=$s_sid; src=file; fi
      [ -n "$cwd" ] || cwd=$s_cwd
    fi
    if [ -z "$sid" ]; then
      sid=$(cmdline_sid "$cmd")
      if is_uuid "$sid"; then src=cmdline; else sid=""; fi
    fi
    [ -n "$resume" ] || resume=$(resume_line "$cwd" "$cmd" "$prof" "$sid" "$role") || resume=""
  fi
  is_caller "$tty" && caller=true
  jq -nc --arg tty "$tty" --arg win "$win" --arg tab "$tab" --arg pid "$pid" --arg kind "$kind" --argjson n "$n" \
    --arg cmd "$cmd" --arg sid "$sid" --arg src "$src" --arg prof "$prof" --arg pdir "$pdir" --arg status "$status" \
    --arg cwd "$cwd" --arg name "$sname" --argjson reg "$reg" --arg issue "$issue" --arg role "$role" \
    --argjson adopted "$adopted" --arg resume "$resume" --argjson caller "$caller" \
    '{tty: $tty, window: $win, tab: $tab, pid: (if $pid == "" then null else ($pid | tonumber) end), kind: $kind,
      processes: $n, command: $cmd, session_id: (if $sid == "" then null else $sid end), id_from: $src,
      profile: $prof, profile_dir: $pdir, status: (if $status == "" then null else $status end), cwd: $cwd,
      name: $name, registered: $reg, issue: (if $issue == "" then null else ($issue | tonumber) end),
      role: (if $role == "" then null else $role end), adopted: $adopted,
      resume: (if $resume == "" then null else $resume end), caller: $caller}'
}

survey_json() { # one JSON line per live tab
  local procs tab tty win
  find_caller
  procs=$(be_procs)
  while read -r tab tty win; do
    [ -n "$tty" ] || continue
    tab_json "$tab" "$tty" "${win:-}" "$procs"
  done <<EOF
$(be_tabs)
EOF
}
