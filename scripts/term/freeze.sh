# shellcheck shell=bash
# freeze.sh: freeze and thaw for scripts/term/term.sh. Sourced by term.sh only.
#
#   term.sh freeze (--all | --group G [--group G2 ...] | --window <group|window id|front> | <tty|session id>...)
#                  [--soft | --hard | --soft-then-hard] [--except <tty|session id>]... [--dry-run] [--local-only]
#   (the mode defaults to term.freeze.default_mode, itself soft-then-hard)
#   term.sh freeze --continue <id>
#
# Order (the snapshot comes first):
#   A. read only: survey, select, then per tab the screen, the state, the session file and an open
#      dialog's question and options. The snapshot .local/freeze/<id>.json is written before any key.
#   B. the record: one "Freeze <id>" issue per owning home (term.group.<g>.home), opened and claimed
#      with home-log under the run id freeze-<id>, then read back. A tab bound to an issue also gets a
#      park checkpoint on that issue. A tab whose record failed is kept and never typed into.
#      A tab whose group comes only from the fallback (general, no matching folder) is unmapped: its
#      details stay in the snapshot and its issue row is one pointer line. Draft text is never read.
#   C. per tab (workers, then orchestrators, then the rest), after the session file's status and the
#      screen agree: hard closes an idle tab with /exit; a dialog gets one Esc once its question was
#      recorded (never an option; a dialog that stays open keeps the tab); a suggestion is cleared by
#      the ghost probe; a real draft keeps the tab (term.freeze.drafts=skip); a running turn is waited
#      on for term.freeze.hard_grace seconds and then kept running (term.freeze.busy=wait).
#      Soft (--soft, and first in --soft-then-hard) types one prompt through the same checks as send (no
#      dialog, no running turn, an empty box, both signals idle; a running turn is never interrupted) asking
#      the session to pause and write .local/freeze/<id>/<session id>.md ending with "nonce: <N>", a random
#      value made per tab. Done means: that file exists, its last line is exactly that nonce line, and the
#      session file says idle (the echo of the prompt on screen proves nothing). Then the tab gets the hard
#      /exit path. At term.freeze.soft_timeout (600 s) --soft keeps the tab (kept:soft-timeout) and types
#      nothing more; --soft-then-hard gives that tab the hard path.
#   D. one home-log checkpoint --park per freeze issue with every outcome and the soft checkpoints of mapped
#      tabs (an unmapped tab's checkpoint stays local), then the lock is released.
# Never touched: the calling session (left open, its resume line recorded), tabs of other tools,
# a tab with more than one claude process, and a session with no resume line (resume: manual).
# Every file is written under this home's .local/. Nothing is signalled; a lingering PID is reported.
# One freeze or thaw at a time (.local/freeze.lock, never stolen).
# Exit: 0 done (see the outcome per tab), 2 usage or an unknown group or window, 3 refused (lock,
# caller not found, nothing to act on), 4 a target not found, 5 a session lingered after /exit.

FREEZE_DIR="$LOCAL_DIR/freeze"
FLOCK="$LOCAL_DIR/freeze.lock"
FLOCK_HELD=0
FID=""; SNAP=""

freeze_unlock() { if [ "$FLOCK_HELD" = 1 ]; then rm -f "$FLOCK/pid"; rmdir "$FLOCK" 2>/dev/null; FLOCK_HELD=0; fi; }

freeze_lock() {
  mkdir -p "$LOCAL_DIR"
  mkdir "$FLOCK" 2>/dev/null ||
    die 3 "another freeze or thaw runs ($FLOCK, holder pid $(cat "$FLOCK/pid" 2>/dev/null || echo '?')); remove it by hand only if that process is gone"
  FLOCK_HELD=1
  echo $$ > "$FLOCK/pid"
}

snap_update() { # snap_update <jq args...>: apply a jq program to the snapshot, atomically
  local tmp
  tmp=$(mktemp "$FREEZE_DIR/.snap.XXXXXX") || return 1
  if jq "$@" "$SNAP" > "$tmp" 2>/dev/null && jq -e '.entries | type == "array"' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$SNAP"
  else
    rm -f "$tmp"; return 1
  fi
}

snap_outcome() { # snap_outcome <tty> <outcome>; rc 1 when the snapshot could not be written
  snap_update --arg t "$1" --arg o "$2" '.entries |= map(if .tty == $t then .outcome = $o else . end)' ||
    { note "snapshot not updated for $1"; return 1; }
}

freeze_opt() { # freeze_opt <drafts|busy>: the conservative value; an opt-in value waits for the owner's approval
  local v
  case "$1" in
    drafts) v=$(cfg term.freeze.drafts skip); [ "$v" = skip ] || note "term.freeze.drafts=$v waits for the owner's approval; using skip"; echo skip ;;
    busy) v=$(cfg term.freeze.busy wait); [ "$v" = wait ] || note "term.freeze.busy=$v waits for the owner's approval; using wait"; echo wait ;;
  esac
}

secs_cfg() { local v; v=$(cfg "$1" "$2"); case "$v" in ''|*[!0-9]*) die 3 "$1 must be a whole number of seconds, not '$v'" ;; esac; echo "$v"; }

agree() { # agree <screen state> <session file status>: the two signals say the same
  case "$1:$2" in
    idle:idle|draft:idle|bg:idle|headsup:idle|busy:busy|dialog:waiting) return 0 ;;
  esac
  return 1
}

dialog_options() { # dialog_options <screen> -> the listed options, one per line
  printf '%s\n' "$1" | LC_ALL=C awk -v P="$PROMPT" '
    { s = $0; sub(/^[ \t]+/, "", s); if (index(s, P) == 1) s = substr(s, length(P) + 1); sub(/^[ \t]+/, "", s)
      if (s ~ /^[0-9]+\.[ \t]/) print s }'
}

# ------------------------------------------------------------------ selecting

select_tabs() { # select_tabs <all json array> <mode> <values json array> -> json array of selected tabs
  case "$2" in
    all) printf '%s' "$1" ;;
    group) printf '%s' "$1" | jq -c --argjson v "$3" '[.[] | select(.group as $g | $v | index($g))]' ;;
    window) printf '%s' "$1" | jq -c --argjson v "$3" '[.[] | select(.window as $w | $v | index($w))]' ;;
    targets) printf '%s' "$1" | jq -c --argjson v "$3" '[.[] | select(. as $t | any($v[]; . as $x |
               $x == $t.tty or (($x | length) >= 8 and (($t.session_id // "") | startswith($x)))))]' ;;
  esac
}

target_tty() { local t=${1#/dev/}; printf '%s\n' "$t"; }

# ------------------------------------------------------------------ the record (phase B)

freeze_body() { # freeze_body <repo> <redact 0|1> -> the issue body for that home
  jq -r --arg r "$1" --arg id "$FID" --arg from "$HOME_REPO" --argjson red "$2" '
    def clean: tostring | gsub("[|\r\n]"; " ");
    def q: if .question == null then "-" elif $red == 1 then "question saved locally: contained sensitive text"
           else (.question | clean | .[0:200]) end;
    [.entries[] | select(.home == $r and .recorded)] as $rows
    | ($rows | map(select(.local | not))) as $full
    | ($rows | map(select(.local))) as $ptr
    | "Freeze \($id): \($rows | length) sessions, frozen by term.sh from \($from).",
      "",
      (if ($full | length) > 0 then
        "| Group | Name | Folder | Profile | Session | State | Open question | Resume |",
        "|---|---|---|---|---|---|---|---|",
        ($full[] | "| \(.group) | \(.name | clean) | \(.cwd | clean) | \(.profile) | \(.session_id) | \(if .caller then "caller (left open)" else .state end) | \(q) | `\(.resume | clean)` |")
       else empty end),
      (if ($ptr | length) > 0 then "",
        ($ptr[] | "- \(.session_id): unmapped tab; its details stay in the running home (.local/freeze/\($id).json)")
       else empty end),
      "",
      "<!-- freeze-data \({id: $id, from: $from, entries: [$rows[] | if .local then {session_id, local: true}
           else {session_id, group, cwd, profile, profile_dir, role, issue, resume, state, caller,
                 question: (if $red == 1 or .question == null then null else (.question | .[0:200]) end)} end]}
           | tojson | gsub("--"; "-\\u002d")) -->"
  ' "$SNAP"
}

freeze_record() { # phase B for one repo: open and claim the issue, read it back; prints the issue number
  local repo=$1 bf n rc red=0 body
  bf="${FREEZE_DIR:?}/${FID:?}.body"
  while :; do
    freeze_body "$repo" "$red" > "$bf" || { rm -f "$bf"; return 1; }
    n=$("$HOME_LOG" new --repo "$repo" --run-id "freeze-$FID" --start \
        --title "Freeze $FID: $(jq --arg r "$repo" '[.entries[] | select(.home == $r and .recorded)] | length' "$SNAP") sessions" \
        --body-file "$bf" 2>>"$FREEZE_DIR/$FID.log")
    rc=$?
    [ "$rc" = 4 ] && [ "$red" = 0 ] && { red=1; note "the record for $repo held sensitive text; retrying with the questions kept locally"; continue; }
    break
  done
  rm -f "$bf"
  [ "$rc" = 0 ] || { note "home-log could not open the freeze issue in $repo (exit $rc)"; return 1; }
  case "$n" in ''|*[!0-9]*) note "home-log printed no issue number for $repo"; return 1 ;; esac
  body=$(gh api "repos/$repo/issues/$n" --jq .body 2>/dev/null) || { note "cannot read $repo#$n back"; return 1; }
  case "$body" in *"<!-- freeze-data "*) ;; *) note "$repo#$n holds no freeze data"; return 1 ;; esac
  for sid in $(jq -r --arg r "$repo" '.entries[] | select(.home == $r and .recorded) | .session_id' "$SNAP"); do
    case "$body" in *"$sid"*) ;; *) note "$repo#$n does not list $sid"; return 1 ;; esac
  done
  echo "$n"
}

park_own_issue() { # park_own_issue <entry json>: a tab bound to this home's issue gets today's park checkpoint
  # An orchestrator tab's issue is a child home's issue: never touched. The question goes along only when the
  # tab's group belongs to this home; another home's question stays in that home's freeze issue.
  local issue sid q="" resume qa=()
  issue=$(printf '%s' "$1" | jq -r '.issue // empty')
  [ -n "$issue" ] || return 0
  [ "$(printf '%s' "$1" | jq -r '.role // ""')" = orchestrator ] && return 0
  sid=$(printf '%s' "$1" | jq -r .session_id)
  printf '%s' "$1" | jq -e --arg r "$HOME_REPO" '.home == $r and (.local | not)' >/dev/null &&
    q=$(printf '%s' "$1" | jq -r '.question // empty')
  resume=$(printf '%s' "$1" | jq -r .resume)
  [ -n "$q" ] && qa=(--question "$q")
  "$HOME_LOG" checkpoint "$issue" --run-id "$sid" --park ${qa[@]+"${qa[@]}"} \
    --text "Frozen by term.sh (Freeze $FID). Resume: $resume" >/dev/null 2>>"$FREEZE_DIR/$FID.log"
}

record_adopted() { # record_adopted <entry json>: a tab this home did not open enters the registry before any key
  local e=$1 entry
  printf '%s' "$e" | jq -e '.registered' >/dev/null && return 0
  entry=$(printf '%s' "$e" | jq -c --arg o "$(now_utc)" --arg f "$FID" \
    '{session_id, tty, pid, cwd, issue: null, resume, opened: $o, closed: null, role: "owner", tab,
      match: (if (.session_id as $s | .command | contains($s)) then .session_id else .command end), adopted: true,
      group, group_from, window, frozen: $f}') || return 1
  reg_update --argjson e "$entry" '. + [$e]'
}

# ------------------------------------------------------------------ acting on one tab (phase C)

freeze_tab_hard() { # freeze_tab_hard <entry json>: run in a subshell; prints the outcome; rc 0 exited, 5 linger
  local e=$1 grace end scr st fs b probes=0 escaped=0 dismissed=0 live
  trap reg_unlock EXIT
  T_TTY=$(printf '%s' "$e" | jq -r .tty); T_TAB=$(printf '%s' "$e" | jq -r .tab)
  T_PID=$(printf '%s' "$e" | jq -r .pid); T_SID=$(printf '%s' "$e" | jq -r .session_id)
  T_MATCH=$(printf '%s' "$e" | jq -r 'if (.session_id as $s | .command | contains($s)) then .session_id else .command end')
  live=$(be_tabs | awk -v t="$T_TTY" '$2 == t && !f { print $1; f = 1 }')
  [ "$live" = "$T_TAB" ] || { echo "kept:changed"; return 3; }
  { pid_alive_as "$T_PID" "$T_MATCH" && [ "$(be_pid_tty "$T_PID")" = "$T_TTY" ]; } || { echo "kept:changed"; return 3; }
  grace=$(secs_cfg term.freeze.hard_grace 120)
  end=$((SECONDS + grace))
  while :; do
    scr=$(be_screen "$T_TTY" "$T_TAB") || { echo "kept:gone"; return 4; }
    st=$(state_of "$scr")
    [ "$st" = shell ] && { echo "kept:no-box"; return 3; }
    fs=$(session_of_pid "$T_PID" | cut -d"$US" -f2)
    if ! agree "$st" "$fs"; then
      [ $SECONDS -ge $end ] && { echo "kept:signals-disagree"; return 3; }
      be_sleep "$POLL"; continue
    fi
    case "$st" in
      headsup)
        [ "$dismissed" = 0 ] || { echo "kept:headsup"; return 3; }
        dismissed=1
        dismiss_headsup || { echo "kept:headsup"; return 3; }
        continue ;;
      busy)
        [ $SECONDS -ge $end ] && { echo "kept:busy"; return 3; }   # busy=wait: never interrupted
        be_sleep "$POLL"; continue ;;
      dialog)
        # Esc only on a dialog whose question and options the snapshot holds; any other dialog keeps the tab
        printf '%s' "$e" | jq -e '(.question // "") != "" and ((.options // []) | length) > 0' >/dev/null ||
          { echo "kept:dialog"; return 3; }
        [ "$escaped" = 0 ] || { echo "kept:dialog"; return 3; }
        escaped=1
        be_key "$T_TTY" "$T_TAB" esc || { echo "kept:gone"; return 4; }   # cancels; never answers
        settle
        has_dialog "$(screen_now)" && { echo "kept:dialog"; return 3; }
        continue ;;
      draft|idle|bg)
        b=$(box_text "$scr") || { echo "kept:no-box"; return 3; }
        if [ -n "$b" ]; then
          [ "$probes" -lt 2 ] || { echo "kept:draft"; return 3; }
          probes=$((probes + 1))
          ghost_probe "$b" && continue
          echo "kept:draft"; return 3   # drafts=skip: a real draft keeps the tab
        fi
        break ;;
    esac
  done
  submit /exit
  wait_pid_gone "$T_PID" "$T_MATCH" "$EXIT_WAIT" || { echo "kept:linger"; return 5; }
  exit_shell
  echo exited
}

soft_prompt() { # soft_prompt <checkpoint path> <nonce>
  printf 'Freeze %s: pause now. Do not ask the owner anything and do not start new work. Finish or stop at a safe point (never mid-push, mid-migration or mid-send). Write %s with the headings: What this session is / State / Open questions for the owner (verbatim) / Timers and loops to re-arm / Next step, and as its last line exactly: nonce: %s. If you hold a home issue, also run its home-log checkpoint --park --question. Then stop.' "$FID" "$1" "$2"
}

soft_done() { # soft_done <checkpoint path> <nonce>: the session wrote its file, ending with the nonce, and is idle
  [ -f "$1" ] || return 1
  [ "$(tail -n 1 "$1" | tr -d '\r')" = "nonce: $2" ] || return 1
  [ "$(session_of_pid "$T_PID" | cut -d"$US" -f2)" = idle ]
}

freeze_tab_soft() { # freeze_tab_soft <entry json> <checkpoint path> <nonce>: in a subshell; prints the outcome
  local e=$1 cp=$2 nonce=$3 end scr st fs b sent=0 dismissed=0 probed=""
  trap reg_unlock EXIT
  T_TTY=$(printf '%s' "$e" | jq -r .tty); T_TAB=$(printf '%s' "$e" | jq -r .tab)
  T_PID=$(printf '%s' "$e" | jq -r .pid); T_SID=$(printf '%s' "$e" | jq -r .session_id)
  T_MATCH=$(printf '%s' "$e" | jq -r 'if (.session_id as $s | .command | contains($s)) then .session_id else .command end')
  [ "$(be_tabs | awk -v t="$T_TTY" '$2 == t && !f { print $1; f = 1 }')" = "$T_TAB" ] || { echo "kept:changed"; return 3; }
  { pid_alive_as "$T_PID" "$T_MATCH" && [ "$(be_pid_tty "$T_PID")" = "$T_TTY" ]; } || { echo "kept:changed"; return 3; }
  end=$((SECONDS + $(secs_cfg term.freeze.soft_timeout 600)))
  while [ $SECONDS -lt $end ]; do   # type the prompt only into an idle, empty box
    scr=$(be_screen "$T_TTY" "$T_TAB") || { echo "kept:gone"; return 4; }
    st=$(state_of "$scr")
    fs=$(session_of_pid "$T_PID" | cut -d"$US" -f2)
    if [ "$st" = headsup ] && [ "$fs" = idle ] && [ "$dismissed" = 0 ]; then
      dismissed=1; dismiss_headsup || { echo "kept:headsup"; return 3; }; continue
    fi
    if [ "$st" = draft ] && [ "$fs" = idle ]; then
      b=$(box_text "$scr")
      if [ "$b" != "$probed" ]; then probed=$b; ghost_probe "$b" && continue; fi
    fi
    if [ "$st" = idle ] && [ "$fs" = idle ]; then submit "$(soft_prompt "$cp" "$nonce")"; sent=1; break; fi
    be_sleep "$POLL"
  done
  [ "$sent" = 1 ] || { echo "kept:soft-timeout"; return 3; }
  while :; do   # checked at least once after the prompt was sent
    soft_done "$cp" "$nonce" && { echo checkpointed; return 0; }
    [ $SECONDS -lt $end ] || break
    be_sleep "$POLL"
  done
  echo "kept:soft-timeout"; return 3
}

# ------------------------------------------------------------------ the verb

cmd_freeze() {
  local mode="" sel="" vals="[]" excepts="[]" dry=0 localonly=0 cont="" all chosen n t repo issue out rc
  local e tty sid rows scr st q opts names="[]" g
  [ $# -ge 1 ] || die 2 "usage: freeze (--all | --group G | --window W | <tty|session id>...) [--soft|--hard|--soft-then-hard] [--except T]... [--dry-run] [--local-only] | freeze --continue <id>"
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) [ -z "$sel" ] || [ "$sel" = all ] || die 2 "use one selector: --all, --group, --window or targets"; sel=all; shift ;;
      --group|--window)
        t=${1#--}; [ -z "$sel" ] || [ "$sel" = "$t" ] || die 2 "use one selector: --all, --group, --window or targets"
        [ $# -ge 2 ] && [ -n "$2" ] || die 2 "$1 needs a value"
        sel=$t; vals=$(printf '%s' "$vals" | jq -c --arg v "$2" '. + [$v]'); shift 2 ;;
      --hard|--soft|--soft-then-hard) [ -z "$mode" ] || [ "$mode" = "${1#--}" ] || die 2 "use one mode: --soft, --hard or --soft-then-hard"
        mode=${1#--}; shift ;;
      --except) [ $# -ge 2 ] || die 2 "--except needs a tty or session id"; excepts=$(printf '%s' "$excepts" | jq -c --arg v "$(target_tty "$2")" '. + [$v]'); shift 2 ;;
      --dry-run) dry=1; shift ;;
      --local-only) localonly=1; shift ;;
      --continue) [ $# -ge 2 ] || die 2 "--continue needs a freeze id"; cont=$2; shift 2 ;;
      -*) die 2 "freeze: unknown option '$1'" ;;
      *) [ -z "$sel" ] || [ "$sel" = targets ] || die 2 "use one selector: --all, --group, --window or targets"
         case "$1" in /dev/tty*|tty*) ;; *) printf '%s' "$1" | grep -Eq '^[0-9a-fA-F-]{8,}$' || die 2 "address a tab by tty or session id, never by title ('$1')" ;; esac
         sel=targets; vals=$(printf '%s' "$vals" | jq -c --arg v "$(target_tty "$1")" '. + [$v]'); shift ;;
    esac
  done
  need_helpers claude
  if [ -n "$cont" ]; then freeze_continue "$cont"; return $?; fi
  [ -n "$sel" ] || die 2 "freeze needs a selector: --all, --group G, --window W or targets"
  [ -n "$mode" ] || mode=$(cfg term.freeze.default_mode soft-then-hard)
  case "$mode" in soft|hard|soft-then-hard) ;; *) die 3 "term.freeze.default_mode must be soft, hard or soft-then-hard, not '$mode'" ;; esac
  if [ "$sel" = group ]; then
    for t in $(printf '%s' "$vals" | jq -r '.[]'); do group_known "$t" || die 2 "unknown group '$t'"; done
  fi
  find_caller
  all=$(survey_json | jq -sc .)
  if [ "$sel" = window ]; then
    vals=$(printf '%s' "$vals" | jq -c --arg f "$(be_front_window)" 'map(if . == "front" then $f else . end)')
    for t in $(printf '%s' "$vals" | jq -r '.[]'); do group_known "$t" && names=$(printf '%s' "$names" | jq -c --arg g "$t" '. + [$g]'); done
    for t in $(printf '%s' "$vals" | jq -r '.[]'); do
      if group_known "$t"; then
        vals=$(printf '%s' "$vals" | jq -c --arg g "$t" --arg w "$(window_for_group "$t" "$(printf '%s' "$all" | jq -c '.[]')")" 'map(if . == $g then $w else . end)')
        continue
      fi
      printf '%s' "$all" | jq -e --arg w "$t" 'any(.[]; .window == $w)' >/dev/null || die 2 "unknown window '$t'"
    done
    for t in $(printf '%s' "$vals" | jq -r '.[]'); do   # a window named by its group must hold only that group's sessions
      for g in $(printf '%s' "$all" | jq -r --arg w "$t" '[.[] | select(.window == $w and .kind == "claude" and .group != null) | .group] | unique | .[]'); do
        [ "$(printf '%s' "$names" | jq length)" = 0 ] && continue   # a window named by its id or front
        printf '%s' "$names" | jq -e --arg g "$g" 'index($g) != null' >/dev/null ||
          die 2 "window $t also holds a tab of group '$g'; name the sessions instead"
      done
    done
  fi
  if [ "$IN_SESSION" = 1 ] && [ -z "$CALLER_TTYS" ] && [ "$sel" != targets ]; then
    die 3 "this runs inside a session whose tab cannot be found; --$sel could include it, so nothing is touched"
  fi
  chosen=$(select_tabs "$all" "$sel" "$vals")
  if [ "$sel" = targets ]; then
    for t in $(printf '%s' "$vals" | jq -r '.[]'); do
      printf '%s' "$chosen" | jq -e --arg t "$t" 'any(.[]; .tty == $t or ((.session_id // "") | startswith($t)))' >/dev/null ||
        die 4 "no live tab for '$t'"
    done
  fi
  # what happens to each tab, before anything is read or written
  chosen=$(printf '%s' "$chosen" | jq -c --argjson x "$excepts" --arg me "${CLAUDE_CODE_SESSION_ID:-}" '[.[] |
    . + {plan: (if .caller or ($me != "" and .session_id == $me) then "kept:caller"
                elif .registry_stale then "kept:changed"
                elif .kind != "claude" then "kept:not-claude"
                elif .processes != 1 then "kept:ambiguous"
                elif (.tty as $t | (.session_id // "") as $s | any($x[]; . as $y | $y == $t or (($y | length) >= 8 and ($s | startswith($y)))))
                  then "kept:except"
                elif .resume == null then "kept:no-resume"
                else "act" end)}]')
  n=$(printf '%s' "$chosen" | jq '[.[] | select(.plan == "act")] | length')
  if [ "$dry" = 1 ]; then
    printf '%s' "$chosen" | jq -c '.[]' | while IFS= read -r e; do
      tty=$(printf '%s' "$e" | jq -r .tty)
      st=-; [ "$(printf '%s' "$e" | jq -r .plan)" = act ] && st=$(state_of "$(be_screen "$tty" "$(printf '%s' "$e" | jq -r .tab)" 2>/dev/null)")
      printf '%s\n' "$e" | jq -r --arg st "$st" --arg m "$mode" '"\(.tty) \(.group // "-") \($st) -> \(if .plan == "act" then "\($m) close" else .plan end)"'
    done
    return 0
  fi
  [ "$n" -gt 0 ] || die 3 "nothing to freeze: no selected tab is a Claude Code session that can be reopened"
  freeze_lock
  FID=$(date -u +%Y%m%dT%H%M%SZ)
  mkdir -p "$FREEZE_DIR"
  while [ -e "$FREEZE_DIR/$FID.json" ]; do be_sleep 1; FID=$(date -u +%Y%m%dT%H%M%SZ); done
  SNAP="$FREEZE_DIR/$FID.json"
  # phase A: read only
  rows="[]"
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    tty=$(printf '%s' "$e" | jq -r .tty)
    scr=""; st=""; q=""; opts="[]"
    if [ "$(printf '%s' "$e" | jq -r .plan)" = act ] || [ "$(printf '%s' "$e" | jq -r .caller)" = true ]; then
      scr=$(be_screen "$tty" "$(printf '%s' "$e" | jq -r .tab)" 2>/dev/null) || scr=""
      if [ -n "$scr" ]; then
        st=$(state_of "$scr")
        if [ "$st" = dialog ]; then
          q=$(dialog_question "$scr") || q=""   # not read: the dialog counts as not recorded
          opts=$(dialog_options "$scr" | jq -R . | jq -sc .)
        fi
      fi
    fi
    repo=""; [ -n "$(printf '%s' "$e" | jq -r '.group // empty')" ] && repo=$(group_repo "$(printf '%s' "$e" | jq -r .group)")
    rows=$(printf '%s' "$rows" | jq -c --argjson e "$e" --arg st "$st" --arg q "$q" --argjson o "$opts" --arg h "$repo" \
      --arg tail "$(screen_tail "$scr" 20)" \
      '. + [$e + {state: (if $st == "" then null else $st end), question: (if $q == "" then null else $q end), options: $o,
         box: "not probed", screen_tail: $tail, home: (if $h == "" then null else $h end), local: ($e.group_from == "fallback"),
         recorded: false, outcome: (if $e.plan == "act" then "captured" else $e.plan end)}]')
  done <<EOF
$(printf '%s' "$chosen" | jq -c '.[]')
EOF
  jq -n --arg id "$FID" --arg c "$(now_utc)" --arg mode "$mode" --arg sel "$sel" --argjson v "$vals" --argjson rows "$rows" \
    '{id: $id, created: $c, mode: $mode, selector: {kind: $sel, values: $v}, records: [], entries: $rows}' > "$SNAP.tmp" &&
    mv "$SNAP.tmp" "$SNAP" || die 3 "cannot write the snapshot; nothing was typed"
  chmod 600 "$SNAP" 2>/dev/null
  # phase B: the record, read back, before any key
  snap_update '.entries |= map(.recorded = ((.outcome == "captured" or .outcome == "kept:caller") and .home != null))' ||
    die 3 "cannot update the snapshot; nothing was typed"
  snap_update '.entries |= map(if .outcome == "captured" and .home == null then .outcome = "kept:no-record" else . end)' ||
    die 3 "cannot update the snapshot; nothing was typed"
  if [ "$localonly" = 0 ]; then
    for repo in $(jq -r '[.entries[] | select(.recorded) | .home] | unique | .[]' "$SNAP"); do
      if issue=$(freeze_record "$repo"); then
        snap_update --arg r "$repo" --arg n "$issue" '.records += [{repo: $r, issue: ($n | tonumber)}]' ||
          die 3 "cannot update the snapshot; nothing was typed"
      else
        snap_update --arg r "$repo" '.entries |= map(if .home == $r and .outcome == "captured" then .outcome = "kept:no-record" else . end)' ||
          die 3 "cannot update the snapshot; nothing was typed"
      fi
    done
  fi
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    tty=$(printf '%s' "$e" | jq -r .tty)
    park_own_issue "$e" || { snap_outcome "$tty" "kept:no-record" || die 3 "cannot update the snapshot; nothing was typed"; continue; }
    record_adopted "$e" || { snap_outcome "$tty" "kept:no-record" || die 3 "cannot update the snapshot; nothing was typed"; continue; }
    sid=$(printf '%s' "$e" | jq -r .session_id)
    printf '%s' "$e" | jq -e .registered >/dev/null &&
      { reg_update --arg t "$tty" --arg f "$FID" 'map(if .tty == $t and .closed == null then . + {frozen: $f} else . end)' || note "registry not updated for $tty"; }
  done <<EOF
$(jq -c '.entries[] | select(.outcome == "captured")' "$SNAP")
EOF
  freeze_act
}

freeze_act() { # phase C and D over the snapshot's entries still to act on
  local e tty outcome rc linger=0 sid repo issue of rec mode cp nonce
  mode=$(jq -r .mode "$SNAP")
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    tty=$(printf '%s' "$e" | jq -r .tty)
    sid=$(printf '%s' "$e" | jq -r .session_id)
    outcome=""; rc=0
    if [ "$mode" != hard ]; then
      mkdir -p "$FREEZE_DIR/$FID"
      cp="$FREEZE_DIR/$FID/$sid.md"; nonce=$(be_uuid | tr -d '-')
      outcome=$( freeze_tab_soft "$e" "$cp" "$nonce" ); rc=$?
      outcome=$(printf '%s\n' "$outcome" | tail -1)
      if [ "$outcome" = checkpointed ]; then
        snap_update --arg t "$tty" --arg c "$cp" '.entries |= map(if .tty == $t then .checkpoint = $c else . end)'
        outcome=""
      elif [ "$mode" = soft ] || [ "$outcome" = kept:changed ] || [ "$outcome" = kept:gone ]; then
        :   # soft only: the tab keeps running and nothing more is typed
      else
        outcome=""   # soft-then-hard: this tab gets the hard path
      fi
    fi
    if [ -z "$outcome" ]; then
      outcome=$( freeze_tab_hard "$e" ); rc=$?
      outcome=$(printf '%s\n' "$outcome" | tail -1)
    fi
    [ -n "$outcome" ] || outcome="failed:exit-$rc"
    [ "$rc" = 5 ] && linger=1
    snap_outcome "$tty" "$outcome" || true
    if [ "$outcome" = exited ]; then
      reg_update --arg t "$tty" --arg c "$(now_utc)" --arg f "$FID" \
        'map(if .tty == $t and .closed == null then . + {closed: $c, frozen: $f} else . end)' || note "registry not updated for $tty"
    fi
  done <<EOF
$(jq -c '[.entries[] | select(.outcome == "captured")]
         | sort_by(if .role == "worker" then 0 elif .role == "orchestrator" then 1 else 2 end) | .[]' "$SNAP")
EOF
  # phase D: the outcomes on each freeze issue
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    repo=$(printf '%s' "$rec" | jq -r .repo); issue=$(printf '%s' "$rec" | jq -r .issue)
    of="${FREEZE_DIR:?}/${FID:?}.outcomes"
    freeze_outcomes "$repo" 1 > "$of"
    "$HOME_LOG" checkpoint "$issue" --repo "$repo" --run-id "freeze-$FID" --park --text-file "$of" >/dev/null 2>>"$FREEZE_DIR/$FID.log"
    rc=$?
    if [ "$rc" = 4 ]; then   # sensitive text in a checkpoint: write the outcomes only; the checkpoints stay local
      freeze_outcomes "$repo" 0 > "$of"
      "$HOME_LOG" checkpoint "$issue" --repo "$repo" --run-id "freeze-$FID" --park --text-file "$of" >/dev/null 2>>"$FREEZE_DIR/$FID.log"
      rc=$?
    fi
    [ "$rc" = 0 ] || note "the outcomes could not be written to $repo#$issue"
    rm -f "$of"
  done <<EOF
$(jq -c '.records[]' "$SNAP")
EOF
  freeze_unlock
  jq -r '"FROZEN \(.id): \([.entries[] | select(.outcome == "exited")] | length) closed, \([.entries[] | select(.outcome != "exited")] | length) kept",
         (.entries[] | select(.outcome != "exited") | "  \(.tty) \(.outcome)"),
         (.records[] | "  record: \(.repo)#\(.issue)")' "$SNAP"
  [ "$linger" = 0 ] || return 5
  return 0
}

freeze_outcomes() { # freeze_outcomes <repo> <with checkpoints 0|1>: the phase D text for that home's issue
  local e cp
  jq -r --arg r "$1" '"Outcomes of Freeze \(.id):", (.entries[] | select(.home == $r and .recorded) | "- \(.session_id): \(.outcome)")' "$SNAP"
  [ "$2" = 1 ] || return 0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    cp=$(printf '%s' "$e" | jq -r .checkpoint)
    [ -f "$cp" ] || continue
    printf '\nCheckpoint of %s:\n' "$(printf '%s' "$e" | jq -r .session_id)"
    sed '$d' "$cp"   # the nonce line is not copied
  done <<EOF
$(jq -c --arg r "$1" '.entries[] | select(.home == $r and .recorded and (.local | not) and .checkpoint != null)' "$SNAP")
EOF
}

freeze_continue() { # freeze_continue <id>: act again on the entries not yet closed (the tab must still be the same)
  FID=$1
  case "$FID" in *[!0-9A-Z]*|'') die 2 "not a freeze id: '$1'" ;; esac
  SNAP="$FREEZE_DIR/$FID.json"
  [ -f "$SNAP" ] || die 4 "no snapshot $SNAP"
  freeze_lock
  find_caller
  snap_update --arg c " $CALLER_TTYS " --arg me "${CLAUDE_CODE_SESSION_ID:-}" \
    '.entries |= map(if ((.tty as $t | $c | contains(" " + $t + " ")) or ($me != "" and .session_id == $me)) and .outcome != "exited"
                     then .outcome = "kept:caller" else . end)' || die 3 "cannot update the snapshot"
  # retried: a running turn, signals that disagreed, a draft, a soft timeout; never a dialog already cancelled once or a lingering PID
  snap_update '.entries |= map(if .outcome == "kept:busy" or .outcome == "kept:signals-disagree" or .outcome == "kept:draft"
                               or .outcome == "kept:soft-timeout" then .outcome = "captured" else . end)' ||
    die 3 "cannot update the snapshot"
  freeze_act
}
