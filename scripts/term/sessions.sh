# shellcheck shell=bash
# sessions.sh: session identity, groups and windows for scripts/term/term.sh. Sourced by term.sh only.
#
# Identity: Claude Code writes <sessions dir>/<pid>.json (pid, sessionId, cwd, name, status) for each
# live session. term.sessions_dirs (comma-separated globs, default ${CLAUDE_CONFIG_DIR:-~/.claude}/sessions)
# says where; the profile is the name of the folder above "sessions" (none when it is .claude).
# The session id comes from the registry (a tab this home opened), then the session file, then the
# command line. A session with no id gets no resume line ("resume: manual") and is never closed by freeze.
# When the recorded process still runs on the recorded tty and tab and its session file names another id
# (as after /clear), the session moved: the id and the resume line come from the session file ("moved_from"
# names the registry's id) and freeze and park update the entry (follow_session in term.sh), keeping the
# first id as "moved_from": the run on the issue was started under it.
#
# A Codex tab: the Codex SessionStart hook (scripts/hooks/session-start --surface codex) writes
# .local/codex-threads/<tty> (thread id, pid of the codex process, cwd, time). The tab has that thread id
# only while the record names the pid of the one live codex process on the tab, the id's rollout file
# exists under ${CODEX_HOME:-~/.codex}/sessions, the thread is not archived and no "cli" thread for the
# same cwd was created at or after the record's time (as after /new); the thread list is read only from
# Codex's state database. Anything else, a database that cannot be read included: no id, listed only.
#
# The calling session (the one running this script) is found by two signals: the first claude (or codex)
# process above this script's own process, and CLAUDE_CODE_SESSION_ID matched against the session files
# (CODEX_THREAD_ID against the thread records).
#
# Groups and windows (keys read from .local/config only, never from home.config):
#   term.groups=g1,g2                 the groups, in thaw order; "general" always exists and catches the rest
#   term.group.<g>.cwd=~/a,~/b        folders of the group; the longest matching prefix wins
#   term.group.<g>.home=self|<name>   where the group's freeze record goes (a name of homes.* in home.config)
# The group of a tab: its registry entry's group, else the longest cwd prefix, else general (a fallback).
# The window of a group is resolved on each open and never trusted from storage: the window holding most
# live tabs of the group, else the window cached in .local/windows.json while it still exists and holds no
# tab of another group, else a new window (then cached). With no term.groups and no --group, open uses the
# current window as before.

US=$'\x1f'   # field separator that keeps empty fields

is_uuid() { printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; }
first_base() { printf '%s\n' "$1" | awk '{ n = split($1, p, "/"); print p[n] }'; }
launch_name() { # the process name of a Claude Code session (launch.command=codex still means claude for these tabs)
  local c; c=$(local_cfg launch.command claude); c=${c##*/}
  [ "$c" = codex ] && c=claude
  printf '%s\n' "$c"
}
tty_pids() { # tty_pids <tty> <name> [procs]: the PIDs on that tty whose command is <name>
  { if [ $# -ge 3 ]; then printf '%s\n' "$3"; else be_procs; fi; } |
    awk -v t="$1" -v c="$2" '$2 == t { n = split($3, p, "/"); if (p[n] == c) print $1 }'
}

session_globs() { # one glob per line from term.sessions_dirs, "~/" expanded
  local v d
  v=$(local_cfg term.sessions_dirs "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions")
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
  lcmd=$(local_cfg launch.command claude); [ "${lcmd##*/}" = codex ] && lcmd=claude
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

# ------------------------------------------------------------------ Codex tabs

codex_resume_line() { printf 'cd %s && codex resume %s\n' "$(shq "${1:-.}")" "$2"; }   # codex_resume_line <cwd> <thread id>

codex_thread() { # codex_thread <tty> <pid of the one codex process on it> -> "thread id US cwd"; rc 1 = no id, listed only
  local f="$LOCAL_DIR/codex-threads/$1" id rpid at cwd home r rows
  [ -f "$f" ] || return 1
  IFS=$US read -r id rpid at cwd <<EOF
$(jq -r '[(.id // ""), (.pid // "" | tostring), (.time // "" | tostring), (.cwd // "")] | join("\u001f")' "$f" 2>/dev/null)
EOF
  is_uuid "$id" && [ -n "$2" ] && [ "$rpid" = "$2" ] || return 1
  case "$at" in ''|*[!0-9]*) return 1 ;; esac
  home=${CODEX_HOME:-$HOME/.codex}
  r=""; for r in "$home"/sessions/*/*/*/rollout-*-"$id".jsonl; do [ -f "$r" ] && break; r=""; done
  [ -n "$r" ] || return 1
  rows=$(be_codex_threads "$home") || return 1
  printf '%s\n' "$rows" | awk -F"$US" -v id="$id" -v at="$at" -v cwd="$cwd" '
    $1 == id { if ($3 != 0) bad = 1; next }
    $4 == "cli" && $5 == cwd && $2 + 0 >= at + 0 { bad = 1 }
    END { exit bad }' || return 1
  printf '%s%s%s\n' "$id" "$US" "$cwd"
}

# ------------------------------------------------------------------ groups and windows

groups_list() { # the configured groups, then general
  printf '%s\n' "$(local_cfg term.groups)" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep . | grep -vx general
  echo general
}

group_known() { groups_list | grep -xF -- "$1" >/dev/null; }

real_dir() { # real_dir <path>: "~/" expanded and symlinks resolved when the folder exists
  local d=$1
  case "$d" in "~/"*) d="$HOME/${d#\~/}" ;; esac
  (cd "$d" 2>/dev/null && pwd -P) || printf '%s\n' "${d%/}"
}

group_of_cwd() { # group_of_cwd <cwd> -> "<group> cwd" for the longest matching prefix, else "general fallback"
  local cwd=$1 g p best="" blen=0 list
  if [ -n "$cwd" ]; then
    while IFS= read -r g; do
      list=$(local_cfg "term.group.$g.cwd")
      [ -n "$list" ] || continue
      while IFS= read -r p; do
        p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); [ -n "$p" ] || continue
        p=$(real_dir "$p")
        case "$cwd/" in "$p/"*) [ ${#p} -gt $blen ] && { best=$g; blen=${#p}; } ;; esac
      done <<EOF
$(printf '%s\n' "$list" | tr ',' '\n')
EOF
    done <<EOF
$(groups_list)
EOF
  fi
  if [ -n "$best" ]; then echo "$best cwd"; else echo "general fallback"; fi
}

group_repo() { # group_repo <group> -> the repo its freeze record goes to (empty when its home is unknown)
  local h
  h=$(local_cfg "term.group.$1.home" self)
  if [ "$h" = self ]; then printf '%s\n' "$HOME_REPO"; else cfg "homes.$h.repo"; fi
}

WINDOWS="$LOCAL_DIR/windows.json"

window_for_group() { # window_for_group <group> <survey --json lines> -> a window id, or "new"
  local g=$1 w cached
  w=$(printf '%s\n' "$2" | jq -rs --arg g "$g" '[.[] | select(.group == $g)] | group_by(.window)
    | map({w: .[0].window, n: length}) | sort_by(-.n) | .[0].w // empty' 2>/dev/null)
  [ -n "$w" ] && { echo "$w"; return 0; }
  cached=$(jq -r --arg g "$g" '[.[] | select(.group == $g)] | last | .window // empty' "$WINDOWS" 2>/dev/null)
  if [ -n "$cached" ] &&
     printf '%s\n' "$2" | jq -es --arg w "$cached" 'any(.[]; .window == $w)' >/dev/null 2>&1 &&
     ! printf '%s\n' "$2" | jq -es --arg w "$cached" --arg g "$g" 'any(.[]; .window == $w and .group != null and .group != $g)' >/dev/null 2>&1; then
    echo "$cached"; return 0
  fi
  echo new
}

cache_window() { # cache_window <group> <window id>: remember the group's window in .local/windows.json
  local tmp cur=$WINDOWS
  [ -n "$2" ] || return 0
  [ -f "$cur" ] || cur=/dev/null
  tmp=$(mktemp "$LOCAL_DIR/windows.json.XXXXXX") || return 1
  if { [ "$cur" = /dev/null ] && echo '[]' || cat "$cur"; } |
     jq --arg g "$1" --arg w "$2" --arg c "$(now_utc)" '[.[] | select(.group != $g)] + [{group: $g, window: $w, created: $c}]' > "$tmp" 2>/dev/null; then
    mv "$tmp" "$WINDOWS"
  else
    rm -f "$tmp"; return 1
  fi
}

# ------------------------------------------------------------------ the calling session

CALLER_TTYS=""; IN_SESSION=0

find_caller() { # sets CALLER_TTYS (ttys found by either signal) and IN_SESSION
  local pid n=0 cmd name tty d f p
  CALLER_TTYS=""; IN_SESSION=0
  name=$(launch_name)
  [ -n "${CLAUDE_CODE_SESSION_ID:-}${CODEX_THREAD_ID:-}" ] && IN_SESSION=1
  pid=$(be_self_pid)
  while [ $n -lt 64 ]; do   # signal 1: the first claude process above this one
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
    cmd=$(be_pid_cmd "$pid") || break
    if [ "$(first_base "$cmd")" = "$name" ] || [ "$(first_base "$cmd")" = codex ]; then
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
  if [ -n "${CODEX_THREAD_ID:-}" ]; then   # signal 2 for Codex: the thread id named by the environment
    for f in "$LOCAL_DIR"/codex-threads/*; do
      [ -f "$f" ] || continue
      p=$(jq -r --arg s "$CODEX_THREAD_ID" 'select(.id == $s) | .pid // empty' "$f" 2>/dev/null)
      case "$p" in ''|*[!0-9]*) continue ;; esac
      cmd=$(be_pid_cmd "$p") || continue
      [ "$(first_base "$cmd")" = codex ] && [ "$(be_pid_tty "$p")" = "${f##*/}" ] || continue
      CALLER_TTYS="$CALLER_TTYS ${f##*/}"
    done
  fi
  return 0
}

is_caller() { case " $CALLER_TTYS " in *" $1 "*) return 0 ;; esac; return 1; }

# ------------------------------------------------------------------ survey --json

tab_json() { # tab_json <tab id> <tty> <window> <procs>: one JSON object for a live tab
  local tab=$1 tty=$2 win=$3 procs=$4 name pids n=0 pid="" kind=shell cmd="" cwd="" sid="" src=none
  local sf="" status="" prof="" pdir="" sname="" entry="" reg=false issue="" role="" adopted=false resume="" caller=false
  local group="" gfrom="" stale=false ct="" moved=""
  name=$(launch_name)
  pids=$(tty_pids "$tty" "$name" "$procs")
  n=$(printf '%s\n' "$pids" | grep -c .)
  if [ "$n" -ge 1 ]; then
    kind=claude; pid=$(printf '%s\n' "$pids" | head -1)
  else
    pids=$(tty_pids "$tty" codex "$procs")
    if [ -n "$pids" ]; then kind=codex; n=$(printf '%s\n' "$pids" | grep -c .); pid=$(printf '%s\n' "$pids" | head -1); fi
  fi
  if [ "$kind" = codex ] && [ "$n" = 1 ]; then   # a thread id only from a record that matches the live tab
    cmd=$(be_pid_cmd "$pid" | head -1)
    cwd=$(be_pid_cwd "$pid")
    entry=$(reg_read -c --arg t "$tty" --arg tab "$tab" '[.[] | select(.tty == $t and .closed == null and (.tab == null or .tab == $tab))] | last // empty')
    if ct=$(codex_thread "$tty" "$pid"); then
      sid=${ct%%"$US"*}; src=codex-record
      [ -n "$cwd" ] || cwd=${ct#*"$US"}
      resume=$(codex_resume_line "${ct#*"$US"}" "$sid")
    fi
    if [ -n "$entry" ]; then
      reg=true
      issue=$(printf '%s' "$entry" | jq -r '.issue // ""')
      role=$(printf '%s' "$entry" | jq -r '.role // "worker"')
      printf '%s' "$entry" | jq -e '.adopted == true' >/dev/null && adopted=true
      printf '%s' "$entry" | jq -e --arg p "$pid" --arg s "$sid" '(.pid | tostring) == $p and .session_id == $s' >/dev/null ||
        { stale=true; sid=""; src=none; resume=""; }
    fi
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
      if printf '%s' "$entry" | jq -e '.match == .session_id or .moved_from != null' >/dev/null; then
        sid=$(printf '%s' "$entry" | jq -r '.session_id'); src=registry
        resume=$(printf '%s' "$entry" | jq -r '.resume // ""')
      fi
      # the registry speaks for this tab only while its pid is the live one
      printf '%s' "$entry" | jq -e --arg p "$pid" '(.pid | tostring) == $p' >/dev/null || stale=true
    fi
    if sf=$(session_of_pid "$pid"); then
      IFS=$US read -r s_sid status s_cwd sname prof pdir <<EOF
$sf
EOF
      if [ "$src" = registry ] && [ "$stale" = false ] && is_uuid "$s_sid" && [ "$s_sid" != "$sid" ]; then
        moved=$sid; sid=""; src=none; resume=""   # the same process, a new session id: the session moved
      fi
      if [ "$stale" = true ]; then sid=""; src=none; resume=""; fi
      if [ -z "$sid" ] && is_uuid "$s_sid"; then sid=$s_sid; src=file; fi
      [ -n "$cwd" ] || cwd=$s_cwd
    fi
    if [ -z "$sid" ]; then
      sid=$(cmdline_sid "$cmd")
      if is_uuid "$sid"; then src=cmdline; else sid=""; fi
    fi
    [ -n "$resume" ] || resume=$(resume_line "$cwd" "$cmd" "$prof" "$sid" "$role") || resume=""
    group=$(printf '%s' "$entry" | jq -r '.group // empty' 2>/dev/null)
    if [ -n "$group" ]; then gfrom=$(printf '%s' "$entry" | jq -r '.group_from // "registry"'); else read -r group gfrom <<EOF
$(group_of_cwd "$cwd")
EOF
    fi
  fi
  is_caller "$tty" && caller=true
  jq -nc --arg tty "$tty" --arg win "$win" --arg tab "$tab" --arg pid "$pid" --arg kind "$kind" --argjson n "$n" \
    --arg cmd "$cmd" --arg sid "$sid" --arg src "$src" --arg prof "$prof" --arg pdir "$pdir" --arg status "$status" \
    --arg cwd "$cwd" --arg name "$sname" --argjson reg "$reg" --arg issue "$issue" --arg role "$role" \
    --argjson adopted "$adopted" --arg resume "$resume" --argjson caller "$caller" --arg group "$group" --arg gfrom "$gfrom" --argjson stale "$stale" --arg moved "$moved" \
    '{tty: $tty, window: $win, tab: $tab, pid: (if $pid == "" then null else ($pid | tonumber) end), kind: $kind,
      processes: $n, command: $cmd, session_id: (if $sid == "" then null else $sid end), id_from: $src,
      profile: $prof, profile_dir: $pdir, status: (if $status == "" then null else $status end), cwd: $cwd,
      name: $name, registered: $reg, issue: (if $issue == "" then null else ($issue | tonumber) end),
      role: (if $role == "" then null else $role end), adopted: $adopted,
      resume: (if $resume == "" then null else $resume end), caller: $caller,
      group: (if $group == "" then null else $group end), group_from: (if $gfrom == "" then null else $gfrom end),
      registry_stale: $stale, moved_from: (if $moved == "" then null else $moved end)}'
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
