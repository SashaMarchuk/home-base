# shellcheck shell=bash
# recover.sh: after a reboot or a crash, for scripts/term/term.sh. Sourced by term.sh only (after thaw.sh).
#
#   term.sh reconcile [--dry-run]
#   term.sh adopt <tty>... [--issue N] [--repo OWNER/REPO] [--group G] | adopt --all [--group G]
#   term.sh reopen [--lost | <session id>...] [--dry-run] [--message TEXT]
#   term.sh forget <session id> [--reason TEXT]
#   term.sh regroup [--dry-run]
#
# reconcile: an open registry entry whose session runs nowhere it was recorded is marked "lost": <time>. It is
# alive only while a live tab has its recorded tab id on its recorded tty AND the session runs there (its recorded
# PID runs its command on that tty, or a claude or codex process on that tty carries its session id); lost when
# its tab is gone or no longer runs it (a tab restored with the same id and a fresh shell) AND that process is
# gone. Its tty, tab and pid move to lost_tty, lost_tab and lost_pid, so no tty lookup matches it again. Silence
# never decides: a tab gone while the process runs, or an entry with no tab or no pid recorded, is left, and when the tabs or the processes cannot be read (or no tab is
# live at all) nothing is marked. One line per change ("LOST <session id> <tty>"); a second run changes nothing.
# survey, status and finished stay read only and never run it: adopt and reopen run it first.
#
# adopt: records a live tab this home did not open, typing nothing: session id, resume line (with the profile
# and model), cwd, window and group (the --group given, else the cwd rules) come from survey --json; the entry has
# "adopted": true and role "owner", so close and park still need --adopt on it and finished keeps it
# (keep:owner-tab). --issue is recorded as the owner named it (--repo too, read by reopen). A tab with no session
# id, more than one session process or one registered already is skipped; the last entry of the same session id
# that was lost or closed is taken over instead of a second one, and an open entry of this tty and tab whose
# recorded PID is dead while its session id runs here again (resumed by hand) takes the new PID ("UPDATED").
# --all adopts every live claude tab not registered yet, never this session's own (name its tty to adopt it).
# Exit 3 when a named tab was skipped, 4 when a named tty has no live tab (3 wins when both happen).
#
# reopen: after a reboot, reopens lost entries (all, or the session ids given), each in its group's window (the
# window logic of open and thaw), in term.groups order, with its recorded resume line and one message: --message,
# else a re-ask of the open question when the run's last home-log comment on its issue holds one, else a short
# "reopened after a restart" note. Skipped: a session that runs already (its id is live in survey --json or on a
# process's command line), a Codex entry, an entry with no resume line and no recorded profile or model to
# rebuild it from (a line missing or lacking them is rebuilt from those fields only), and an entry whose issue
# is closed, whose run's claim comment says final or released, or whose issue's last home-log comment is of
# another run (read with gh; an issue that cannot be read is skipped too, never reopened unchecked). Memory is
# checked before each tab (a refusal stops with exit 3), workers are queued at term.max_workers. reopen holds the
# lock freeze and thaw use (a second reopen, freeze or thaw exits 3) and reserves each entry only while it is
# still lost. A tab that could not be opened leaves the entry lost (reopen tries it again); a tab that opened
# without its process is left closed and named; a tab that opened while the registry could not record it is
# named with its tty and never reopened again (term.sh adopt <tty> records it).
#
# forget: a lost entry that must not come back (its work is done or taken over) is closed with closed_reason
# "forgotten[: <reason>]" (lost is cleared, lost_tty, lost_tab and lost_pid stay); nothing is typed and no tab is touched. An entry that is not lost is refused (exit 3).
#
# regroup: lists the registered live tabs that are not in their group's window (the window holding most of the
# group's tabs). The iTerm2 AppleScript backend cannot move a tab to another window (its dictionary has no move
# for a tab), so nothing is moved: --dry-run prints the plan and exits 0; without it the plan is printed and it
# exits 3 saying so.

lost_scan() { # lost_scan <live tabs> <procs> -> one JSON line per open entry whose session runs nowhere it was recorded
  # Alive: a live tab has the recorded tab id on the recorded tty AND the session runs there (its recorded PID runs
  # its command on that tty, or a claude or codex process on that tty carries its session id on its command line).
  # Lost: its tab is gone or no longer runs it (iTerm2 may restore a window with the same tab ids and fresh
  # shells) AND its process is gone: two signals. A tab gone while the process still runs is one signal: left.
  local e sid tab tty pid match name tab_live runs
  name=$(launch_name)
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    IFS=$US read -r sid tab tty pid match <<EOF
$(printf '%s' "$e" | jq -r '[.session_id, .tab, .tty, (.pid | tostring), (.match // "")] | join("\u001f")')
EOF
    tab_live=0; runs=0
    printf '%s\n' "$1" | awk -v t="$tab" -v y="$tty" '$1 == t && $2 == y { f = 1 } END { exit !f }' && tab_live=1
    if printf '%s\n' "$2" | awk -v p="$pid" '$1 == p { f = 1 } END { exit !f }' &&
       pid_alive_as "$pid" "$match" && [ "$(be_pid_tty "$pid")" = "$tty" ]; then
      runs=1
    elif printf '%s\n' "$2" | awk -v y="$tty" -v s="$sid" -v n="$name" \
        '$2 == y && index($0, s) > 0 { k = split($3, p, "/"); if (p[k] == n || p[k] == "codex") f = 1 } END { exit !f }'; then
      runs=1   # resumed by hand in its tab (a new PID, the same session id)
    fi
    [ "$tab_live" = 1 ] && [ "$runs" = 1 ] && continue   # alive
    [ "$runs" = 1 ] && continue                           # tab gone, process runs: one signal only
    printf '%s\n' "$e"
  done <<EOF
$(reg_read -c '.[] | select(.closed == null and .lost == null and .tty != null and .tab != null and .pid != null)')
EOF
}

lost_now() { # lost_now -> lost_scan over the live tabs and processes; exit 3 when either cannot be read
  local tabs procs
  tabs=$(be_tabs) || die 3 "the terminal's tabs cannot be read; nothing is marked lost"
  [ -n "$(printf '%s' "$tabs" | tr -d '[:space:]')" ] || die 3 "no live tab could be read; nothing is marked lost (silence never decides)"
  procs=$(be_procs) || die 3 "the process list cannot be read; nothing is marked lost"
  [ -n "$procs" ] || die 3 "the process list is empty; nothing is marked lost"
  lost_scan "$tabs" "$procs"
}

reconcile_pass() { # reconcile_pass <dry 0|1>: mark lost entries (or list them); prints one line per entry
  local e sid tty found
  found=$(lost_now) || exit $?
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    sid=$(printf '%s' "$e" | jq -r .session_id); tty=$(printf '%s' "$e" | jq -r .tty)
    if [ "$1" = 1 ]; then echo "PLAN lost $sid $tty"; continue; fi
    # written only while the entry still names the tab and process that were found gone
    reg_update --argjson e "$e" --arg c "$(now_utc)" 'map(if .session_id == $e.session_id and .tty == $e.tty and .tab == $e.tab
        and .pid == $e.pid and .closed == null and .lost == null
      then . + {lost: $c, lost_tty: .tty, lost_tab: .tab, lost_pid: .pid, tty: null, tab: null, pid: null} else . end)' ||
      die 3 "registry write failed"
    echo "LOST $sid $tty"
  done <<EOF
$found
EOF
}

cmd_reconcile() {
  local dry=0
  while [ $# -gt 0 ]; do
    case "$1" in --dry-run) dry=1; shift ;; *) die 2 "usage: reconcile [--dry-run]" ;; esac
  done
  need_helpers
  reconcile_pass "$dry"
}

# ------------------------------------------------------------------ adopt

adopt_row() { # adopt_row <survey row> <issue> <repo> <group> <named 0|1>: record one live tab; prints the outcome; rc 3 = skipped
  local r=$1 tty sid kind n entry old gfrom=""
  tty=$(printf '%s' "$r" | jq -r .tty); sid=$(printf '%s' "$r" | jq -r '.session_id // ""'); kind=$(printf '%s' "$r" | jq -r .kind)
  n=$(printf '%s' "$r" | jq -r .processes)
  case "$kind" in claude|codex) ;; *) echo "SKIP $tty: no session runs on it"; return 3 ;; esac
  [ "$n" = 1 ] || { echo "SKIP $tty: $n $kind processes run on it; not guessing which one"; return 3; }
  if printf '%s' "$r" | jq -e '.registered and (.registry_stale | not)' >/dev/null; then
    echo "SKIP $tty: registered already ($(printf '%s' "$r" | jq -r '.session_id // "-"'))"; return 3
  fi
  [ "$5" = 1 ] || ! printf '%s' "$r" | jq -e .caller >/dev/null || { echo "SKIP $tty: this session's own tab (name its tty to adopt it)"; return 3; }
  is_uuid "$sid" || { echo "SKIP $tty: no session id, so it could not be reopened; not adopted"; return 3; }
  old=$(reg_read -c --arg s "$sid" '[.[] | select(.session_id == $s)] | last // empty')
  if [ -n "$old" ] && printf '%s' "$old" | jq -e '.closed == null and .lost == null' >/dev/null; then
    # resumed by hand in its own tab after a crash (the entry names this tty and tab and its recorded PID is dead), or
    # a reservation whose tab opened while the registry could not record it (no tty and no PID recorded)
    if printf '%s' "$old" | jq -e --argjson r "$r" '(.tty == $r.tty and (.tab == null or .tab == $r.tab) and .pid != $r.pid)
        or (.tty == null and .pid == null)' >/dev/null &&
       ! { pid_alive_as "$(printf '%s' "$old" | jq -r '.pid // ""')" "$(printf '%s' "$old" | jq -r '.match // ""')" &&
           [ "$(be_pid_tty "$(printf '%s' "$old" | jq -r .pid)")" = "$tty" ]; }; then
      reg_update --argjson r "$r" '(to_entries | map(select(.value.session_id == $r.session_id)) | last | .key) as $i
          | .[$i] |= (. + {pid: $r.pid, tab: $r.tab, tty: $r.tty, window: ($r.window // .window),
              match: (if ($r.command | contains($r.session_id)) then $r.session_id else $r.command end)})' ||
        { echo "SKIP $tty: registry write failed"; return 3; }
      echo "UPDATED $tty $sid: it runs again in its recorded tab (PID $(printf '%s' "$r" | jq -r .pid))"; return 0
    fi
    echo "SKIP $tty: session $sid is recorded open on $(printf '%s' "$old" | jq -r '.tty // "no tty"')"; return 3
  fi
  [ -n "$4" ] && gfrom=explicit
  entry=$(printf '%s' "$r" | jq -c --arg o "$(now_utc)" --arg issue "$2" --arg repo "$3" --arg g "$4" --arg gf "$gfrom" \
    --arg model "$(cmdline_opt "$(printf '%s' "$r" | jq -r '.command // ""')" --model)" '
    {session_id, tty, pid, cwd, issue: (if $issue == "" then null else ($issue | tonumber) end),
     repo: (if $repo == "" then null else $repo end), resume, opened: $o, closed: null, role: "owner", tab,
     match: (if (.session_id as $s | .command | contains($s)) then .session_id else .command end), adopted: true,
     group: (if $g == "" then .group else $g end), group_from: (if $gf == "" then .group_from else $gf end), window,
     profile: (if .profile == "" then null else .profile end), model: (if $model == "" then null else $model end)}
    + (if .kind == "codex" then {kind: "codex"} else {} end)') || { echo "SKIP $tty: the entry could not be built"; return 3; }
  if [ -n "$old" ]; then   # a lost or closed entry of this session: it follows the session into this tab
    reg_update --argjson e "$entry" '(to_entries | map(select(.value.session_id == $e.session_id)) | last | .key) as $i
        | .[$i] |= ((. + $e + {issue: ($e.issue // .issue), repo: ($e.repo // .repo), role: (.role // "owner")})
          | del(.lost, .lost_tty, .lost_tab, .lost_pid, .parked))'
  else
    reg_update --argjson e "$entry" '. + [$e]'
  fi || { echo "SKIP $tty: registry write failed"; return 3; }
  echo "ADOPTED $tty $sid $(printf '%s' "$entry" | jq -r '.group // "general"')"
  if printf '%s' "$entry" | jq -e '.resume == null and .profile != null' >/dev/null; then
    echo "NOTE $tty: it runs under profile '$(printf '%s' "$entry" | jq -r .profile)' and launch.profile_flag is empty in .local/config, so it has no resume line (resume: manual) and reopen cannot bring it back until the flag is set"
  fi
}

cmd_adopt() {
  local all=0 issue="" repo="" group="" ttys="" t rows r rc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1; shift ;;
      --issue) [ $# -ge 2 ] && [ -n "$2" ] || die 2 "--issue needs a number"; issue=$2; shift 2 ;;
      --repo) [ $# -ge 2 ] && [ -n "$2" ] || die 2 "--repo needs OWNER/REPO"; repo=$2; shift 2 ;;
      --group) [ $# -ge 2 ] && [ -n "$2" ] || die 2 "--group needs a group name"; group=$2; shift 2 ;;
      /dev/tty*|tty*) t=${1#/dev/}; case "$t" in *[!A-Za-z0-9]*) die 2 "not a tty: '$1'" ;; esac; ttys="$ttys $t"; shift ;;
      *) die 2 "usage: adopt <tty>... [--issue N] [--repo OWNER/REPO] [--group G] | adopt --all [--group G] (a tab is named by its tty)" ;;
    esac
  done
  [ "$all" = 1 ] || [ -n "$ttys" ] || die 2 "usage: adopt <tty>... | adopt --all"
  case "$issue" in *[!0-9]*) die 2 "issue must be a number" ;; esac
  [ -z "$repo" ] || printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || die 2 "--repo takes OWNER/REPO"
  [ -z "$repo" ] || [ -n "$issue" ] || die 2 "--repo names the repo of --issue; give --issue too"
  [ "$all" = 0 ] || [ -z "$issue" ] || die 2 "--issue binds one tab; not with --all"
  [ -z "$issue" ] || [ "$(printf '%s\n' $ttys | grep -c .)" -le 1 ] || die 2 "--issue binds one tab; name one tty"
  need_helpers
  [ -z "$group" ] || group_known "$group" || die 2 "unknown group '$group' (term.groups in .local/config: $(groups_list | tr '\n' ' '))"
  r=$(reconcile_pass 0) || exit $?
  [ -z "$r" ] || printf '%s\n' "$r"
  rows=$(survey_json)
  for t in $ttys; do
    r=$(printf '%s\n' "$rows" | jq -c --arg t "$t" 'select(.tty == $t)' | head -1)
    if [ -z "$r" ]; then echo "SKIP $t: no live tab"; [ "$rc" = 3 ] || rc=4; continue; fi
    adopt_row "$r" "$issue" "$repo" "$group" 1 || rc=3
  done
  if [ "$all" = 1 ]; then
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      case " $ttys " in *" $(printf '%s' "$r" | jq -r .tty) "*) continue ;; esac
      adopt_row "$r" "" "" "$group" 0 || true
    done <<EOF
$(printf '%s\n' "$rows" | jq -c 'select(.kind == "claude" and ((.registered and (.registry_stale | not)) | not))')
EOF
  fi
  return $rc
}

# ------------------------------------------------------------------ reopen

running_ids() { # the session ids that run now: survey --json ids, and --resume/--session-id on any claude command line
  local name pid tty cmd
  name=$(launch_name)
  survey_json | jq -r '.session_id // empty'
  be_procs | while read -r pid tty cmd; do
    [ "$(first_base "$cmd")" = "$name" ] || continue
    cmdline_sid "$cmd"
  done
}

entry_repo() { # entry_repo <entry json> -> the repo of its issue: .repo, else the orchestrator's home, else this home
  local repo cwd
  repo=$(printf '%s' "$1" | jq -r '.repo // empty')
  if [ -z "$repo" ]; then
    repo=$HOME_REPO
    if [ "$(printf '%s' "$1" | jq -r '.role // "worker"')" = orchestrator ]; then
      cwd=$(printf '%s' "$1" | jq -r '.cwd // ""')
      repo=$(cfg_read_file "$cwd/home.config" repo) || repo=""
    fi
  fi
  printf '%s\n' "$repo"
}

reopen_issue_skip() { # reopen_issue_skip <entry json> -> why it must not be reopened (rc 0), or rc 1 to reopen it
  # Read only. The issue is closed, its run's last claim comment says final or released, or the last home-log
  # comment on it is of another run (another session took the issue over or ended it): skipped. Unreadable: skipped.
  local issue repo run raw last
  issue=$(printf '%s' "$1" | jq -r '.issue // empty')
  [ -n "$issue" ] || return 1
  repo=$(entry_repo "$1"); run=$(printf '%s' "$1" | jq -r '.moved_from // .session_id')
  printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ||
    { echo "the repo of issue #$issue is unknown, so the issue cannot be checked"; return 0; }
  raw=$(gh api "repos/$repo/issues/$issue" --jq .state 2>/dev/null) ||
    { echo "cannot read $repo#$issue; not reopened unchecked (retry, or term.sh forget it)"; return 0; }
  [ "$raw" = open ] || { echo "its issue $repo#$issue is $raw"; return 0; }
  raw=$(gh api --paginate "repos/$repo/issues/$issue/comments?per_page=100" 2>/dev/null) ||
    { echo "cannot read the comments of $repo#$issue; not reopened unchecked (retry, or term.sh forget it)"; return 0; }
  # a hand-off note (state=delegated, written by the orchestrator's run) is no claim: it may land after the worker's own
  last=$(printf '%s' "$raw" | jq -rs '[(add // [])[] | .body | capture("^<!-- home-log run=(?<run>[^ ]+) state=(?<state>[a-z]+) -->")?
    | select(.state != "delegated")]
    | last // empty | "\(.run) \(.state)"' 2>/dev/null) ||
    { echo "cannot read the comments of $repo#$issue; not reopened unchecked"; return 0; }
  case "$last" in
    '') return 1 ;;
    "$run final"|"$run released") echo "its run on $repo#$issue is ${last#* }"; return 0 ;;
    "$run "*) return 1 ;;
    *) echo "the last claim comment on $repo#$issue is of another run (${last% *}, ${last#* })"; return 0 ;;
  esac
}

reopen_line() { # reopen_line <entry json> -> its resume line; rebuilt from its recorded profile and model when the
  # recorded line is missing or lacks them (an adopted tab whose profile could not be passed then), never from
  # anything else; empty when there is none
  local e=$1 line sid cwd prof model flag cmd
  line=$(printf '%s' "$e" | jq -r '.resume // empty')
  sid=$(printf '%s' "$e" | jq -r .session_id); cwd=$(printf '%s' "$e" | jq -r '.cwd // "."')
  prof=$(printf '%s' "$e" | jq -r '.profile // empty'); model=$(printf '%s' "$e" | jq -r '.model // empty')
  printf '%s' "$prof" | grep -Eq '^[A-Za-z0-9._@-]+$' || prof=""
  printf '%s' "$model" | grep -Eq '^[a-z]+(\[1m\])?$' || model=""
  flag=$(local_cfg launch.profile_flag)
  [ -n "$flag" ] || prof=""   # a profile that cannot be passed is never guessed
  if [ -n "$prof$model" ] && is_uuid "$sid" && {
       [ -z "$line" ] ||
       { [ -n "$prof" ] && case "$line" in *" $flag $(shq "$prof") "*) false ;; *) true ;; esac; } ||
       { [ -n "$model" ] && case "$line" in *" --model "*) false ;; *) true ;; esac; }; }; then
    cmd="claude"; [ -n "$model" ] && cmd="$cmd --model $model"
    case "$line" in *" --dangerously-skip-permissions"*) cmd="$cmd --dangerously-skip-permissions" ;; esac
    resume_line "$cwd" "$cmd" "$prof" "$sid" && return 0
  fi
  printf '%s\n' "$line"
}

reopen_message() { # reopen_message <entry json> -> the one message for the reopened session
  local issue repo run
  issue=$(printf '%s' "$1" | jq -r '.issue // empty')
  run=$(printf '%s' "$1" | jq -r '.moved_from // .session_id')
  repo=$(entry_repo "$1")
  if [ -n "$issue" ] && printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    run_has_question "$repo" "$issue" "$run"
    case $? in
      0) echo "You were reopened after a restart; your conversation is intact. Re-ask your open question with the ask tool, then continue."; return 0 ;;
      2) note "cannot read $repo#$issue; sending the restart note" ;;
    esac
  fi
  echo "You were reopened after a restart; your conversation is intact. Continue where you stopped, or re-ask your open question with the ask tool if you had one."
}

cmd_reopen() {
  local dry=0 msg="" lost=0 sids="[]" live e sid g p line m win out rc reopened=0 lsids cands why tty
  while [ $# -gt 0 ]; do
    case "$1" in
      --lost) lost=1; shift ;;
      --dry-run) dry=1; shift ;;
      --message) [ $# -ge 2 ] || die 2 "reopen: --message needs a text"; msg=$2; one_line "$msg"; shift 2 ;;
      -*) die 2 "reopen: unknown option '$1'" ;;
      *) printf '%s' "$1" | grep -Eq '^[0-9a-fA-F-]{8,}$' || die 2 "reopen takes --lost or session ids ('$1')"
         sids=$(printf '%s' "$sids" | jq -c --arg v "$1" '. + [$v]'); shift ;;
    esac
  done
  [ "$lost" = 0 ] || [ "$sids" = "[]" ] || die 2 "reopen: use --lost or session ids, not both"
  need_helpers claude
  if [ "$dry" = 1 ]; then
    lsids=$(lost_now) || exit $?
    lsids=$(printf '%s' "$lsids" | jq -sc '[.[].session_id]')   # what reconcile would mark; nothing is written
  else
    freeze_lock   # one reopen, freeze or thaw at a time: a second run exits 3 instead of opening a session twice
    lsids=$(reconcile_pass 0) || exit $?
    [ -z "$lsids" ] || printf '%s\n' "$lsids"
    lsids="[]"
  fi
  for sid in $(printf '%s' "$sids" | jq -r '.[]'); do   # a session id named that is not lost: said, never reopened
    reg_read -e --arg p "$sid" --argjson l "$lsids" 'any(.[]; (.session_id | startswith($p)) and .closed == null
      and (.lost != null or (.session_id as $x | $l | index($x))))' >/dev/null ||
      echo "SKIP $sid: no lost entry has this id (a closed one is reopened with term.sh resume or thaw)"
  done
  live=$(running_ids | jq -R . | jq -sc '[.[] | select(. != "")]')
  cands=""
  while IFS= read -r e; do   # each candidate with its group (recorded, else from its cwd), then in term.groups order
    [ -n "$e" ] || continue
    if [ -z "$(printf '%s' "$e" | jq -r '.group // empty')" ]; then
      read -r g m <<EOF
$(group_of_cwd "$(printf '%s' "$e" | jq -r '.cwd // ""')")
EOF
      e=$(printf '%s' "$e" | jq -c --arg g "$g" --arg m "$m" '. + {group: $g, group_from: $m}')
    fi
    cands="$cands$e
"
  done <<EOF
$(reg_read -c --argjson s "$sids" --argjson l "$lsids" '.[] | select(.closed == null and (.lost != null or (.session_id as $x | $l | index($x))))
   | select(($s | length) == 0 or (.session_id as $x | any($s[]; . as $p | $x | startswith($p))))')
EOF
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    sid=$(printf '%s' "$e" | jq -r .session_id)
    if printf '%s' "$live" | jq -e --arg s "$sid" 'index($s) != null' >/dev/null; then
      echo "SKIP $sid: it runs already (adopt its tab with term.sh adopt <tty> if this home did not open it)"; continue
    fi
    if [ "$(printf '%s' "$e" | jq -r '.kind // "claude"')" = codex ]; then
      echo "SKIP $sid: a Codex session; reopen it by hand: $(printf '%s' "$e" | jq -r '.resume // "(no resume line)"')"; continue
    fi
    line=$(reopen_line "$e")
    case "$line" in *"--resume $sid"*) ;; *) echo "SKIP $sid: no resume line recorded (resume: manual)"; continue ;; esac
    if why=$(reopen_issue_skip "$e"); then echo "SKIP $sid: $why (term.sh forget $sid drops the entry)"; continue; fi
    g=$(printf '%s' "$e" | jq -r .group)
    p=$(role_window "$(printf '%s' "$e" | jq -r '.role // ""')"); [ -n "$p" ] || p=$g
    m=$msg; [ -n "$m" ] || m=$(reopen_message "$e")
    if [ "$dry" = 1 ]; then echo "PLAN $sid -> group $g: $line"; continue; fi
    if ! ( check_memory ) 2>/dev/null; then
      echo "STOPPED: memory is low or cannot be read; $reopened reopened; run 'term.sh reopen --lost' later"
      return 3
    fi
    thaw_reserve "$e" "$line" lost; rc=$?
    if [ "$rc" = 6 ]; then echo "QUEUED $sid: the worker cap is reached; it stays lost"; continue; fi
    if [ "$rc" = 7 ]; then echo "SKIP $sid: another run reopened, adopted or closed it meanwhile"; continue; fi
    [ "$rc" = 0 ] || { echo "SKIP $sid: the registry could not be written"; continue; }
    win=$(window_for_group "$p" "$(survey_json)")
    out=$( launch_tab "$sid" "$line $(shq "$m")" "$sid" "$win" ); rc=$?
    if [ "$rc" != 0 ]; then
      tty=$(printf '%s' "$out" | awk '{ print $2 }')
      if [ "$rc" = 5 ]; then
        echo "FAILED $sid: a tab opened but no session process appeared; it is marked closed (see that tab; term.sh resume $sid)"
      elif [ -n "$tty" ]; then   # a tab opened but the registry could not record it: never marked lost again
        echo "FAILED $sid: a tab opened on $tty but the registry could not be updated; it is not reopened again (check that tab, then term.sh adopt $tty)"
      else   # no tab was opened: it stays lost, so reopen tries it again
        reg_set "$sid" '{closed: null, lost: $c}' --arg c "$(now_utc)" || note "registry not updated for $sid"
        echo "FAILED $sid: the tab did not open; it stays lost"
      fi
      continue
    fi
    if [ "$win" = new ]; then
      cache_window "$p" "$(reg_read -r --arg s "$sid" '.[] | select(.session_id == $s) | .window // empty')" || note "window not cached"
    fi
    reopened=$((reopened + 1))
    echo "REOPENED $sid $(printf '%s' "$out" | awk '{ print $2 }') (group $g)"
  done <<EOF
$(printf '%s' "$cands" | jq -sc --argjson order "$(groups_list | jq -R . | jq -sc .)" 'sort_by(.group as $x | ($order | index($x)) // 999) | .[]')
EOF
  return 0
}

# ------------------------------------------------------------------ forget

cmd_forget() { # forget <session id> [--reason TEXT]: a lost entry that must not come back is closed; nothing is typed
  local sid="" reason="" n
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) [ $# -ge 2 ] && [ -n "$2" ] || die 2 "forget: --reason needs a text"; reason=$2; one_line "$reason"; shift 2 ;;
      -*) die 2 "forget: unknown option '$1'" ;;
      *) [ -z "$sid" ] || die 2 "forget takes one session id"
         printf '%s' "$1" | grep -Eq '^[0-9a-fA-F-]{8,}$' || die 2 "forget takes a session id ('$1')"; sid=$1; shift ;;
    esac
  done
  [ -n "$sid" ] || die 2 "usage: forget <session id> [--reason TEXT]"
  need_helpers
  n=$(reg_read --arg s "$sid" '[.[] | select((.session_id | startswith($s)) and .closed == null)] | length')
  [ "$n" -ge 1 ] || die 4 "no open registry entry has the id '$sid'"
  [ "$n" = 1 ] || die 4 "session id '$sid' matches $n open registry entries"
  sid=$(reg_read -r --arg s "$sid" '.[] | select((.session_id | startswith($s)) and .closed == null) | .session_id')
  reg_read -e --arg s "$sid" 'any(.[]; .session_id == $s and .closed == null and .lost != null)' >/dev/null ||
    die 3 "session $sid is not lost; a live session is closed with term.sh close, never forgotten"
  reg_update --arg s "$sid" --arg c "$(now_utc)" --arg r "forgotten${reason:+: $reason}" \
    'map(if .session_id == $s and .closed == null and .lost != null then . + {closed: $c, closed_reason: $r} | del(.lost) else . end)' ||
    die 3 "registry write failed"
  echo "FORGOTTEN $sid"
}

# ------------------------------------------------------------------ regroup

cmd_regroup() {
  local dry=0 rows plan
  while [ $# -gt 0 ]; do
    case "$1" in --dry-run) dry=1; shift ;; *) die 2 "usage: regroup [--dry-run]" ;; esac
  done
  need_helpers
  rows=$(survey_json)
  # the group's window: the one holding most of its live tabs (as open and thaw pick it); only registered live tabs move
  plan=$(printf '%s\n' "$rows" | jq -sr '
    [.[] | select(.registered and (.registry_stale | not) and (.place // .group) != null) | . + {k: (.place // .group)}] as $t
    | ($t | group_by(.k) | map({key: .[0].k, value: (group_by(.window) | map({w: .[0].window, n: length}) | sort_by(-.n) | .[0].w)}) | from_entries) as $win
    | $t[] | select(.window != $win[.k]) | "MOVE \(.tty) \(.session_id // "-") group \(.k): window \(.window) -> \($win[.k])"')
  if [ -z "$plan" ]; then echo "every registered tab is in its group's window"; return 0; fi
  printf '%s\n' "$plan"
  [ "$dry" = 1 ] && return 0
  note "the iTerm2 AppleScript backend cannot move a tab to another window; nothing was moved (move these tabs by hand)"
  return 3
}
