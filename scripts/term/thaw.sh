# shellcheck shell=bash
# thaw.sh: reopen the sessions of a freeze, for scripts/term/term.sh. Sourced by term.sh only (after freeze.sh).
#
#   term.sh thaw [<id>|latest] [--group G]... [<session id>]... [--issue OWNER/REPO#N] [--dry-run]
#   term.sh thaw --continue <id>
#
# Reopens the sessions of a freeze in their group windows, in term.groups order, each with its resume line
# and one message by class (an open question: re-ask it; a soft checkpoint: read it first; else continue).
# Skipped: a session that is live already (a second resume of one session can lose messages), an entry that
# was not closed, and a session whose transcript is not on this machine (its resume line is printed).
# The snapshot is .local/freeze/<id>.json; when it is missing, --issue reads the freeze-data block of that
# issue (an unmapped tab's details stay on the machine that froze it). Memory is checked before each tab;
# a refusal stops the run and prints what is left. Workers count against term.max_workers; at the cap the
# rest are queued. A dialog shown by a reopened session (such as "resume this conversation?") is never
# answered: thaw types nothing after the launch line. A freeze issue is finished once each of its closed
# sessions is reopened or live already (such as the caller that ran the freeze).
# Exit: 0 done, 2 usage, 3 stopped (memory, lock), 4 no snapshot.

thaw_message() { # thaw_message <entry json> -> the one message for that session
  local cp
  cp=$(printf '%s' "$1" | jq -r '.checkpoint // empty')
  if [ -n "$(printf '%s' "$1" | jq -r '.question // empty')" ]; then
    echo "You were frozen at $FID. Re-ask your open question with the ask tool, then continue."
  elif [ -n "$cp" ] && [ -f "$cp" ]; then
    echo "Read $cp first, re-arm the timers it lists, then continue."
  else
    echo "You were resumed. Continue where you stopped."
  fi
}

thaw_reserve() { # thaw_reserve <entry json> <resume line>: registry entry for the reopened session; rc 6 at the worker cap
  local e=$1 sid role rc
  sid=$(printf '%s' "$e" | jq -r .session_id)
  role=$(printf '%s' "$e" | jq -r '.role // "owner"')
  reg_lock || return 3
  if [ "$role" = worker ] && [ "$(count_live_workers)" -ge "$(cfg term.max_workers 4)" ]; then reg_unlock; return 6; fi
  if [ "$(reg_read --arg s "$sid" '[.[] | select(.session_id == $s)] | length')" -gt 0 ]; then
    reg_write --arg s "$sid" --arg o "$(now_utc)" --arg r "$2" --arg g "$(printf '%s' "$e" | jq -r '.group // ""')" \
      --arg gf "$(printf '%s' "$e" | jq -r '.group_from // ""')" \
      'map(if .session_id == $s then . + {closed: null, parked: false, opened: $o, pid: null, tty: null, tab: null,
         match: $s, resume: $r, group: (if $g == "" then .group else $g end),
         group_from: (if $gf == "" then .group_from else $gf end)} else . end)'
  else
    reg_write --argjson e "$(printf '%s' "$e" | jq -c --arg o "$(now_utc)" --arg r "$2" \
      '{session_id, tty: null, pid: null, cwd, issue, resume: $r, opened: $o, closed: null, role: (.role // "owner"),
        tab: null, match: .session_id, group, group_from, adopted: (.adopted // false)}')" '. + [$e]'
  fi
  rc=$?
  reg_unlock
  return $rc
}

has_transcript() { # has_transcript <profile dir> <session id>
  local f
  [ -n "$1" ] || return 1
  for f in "$1"/projects/*/"$2".jsonl; do [ -f "$f" ] && return 0; done
  return 1
}

snapshot_from_issue() { # snapshot_from_issue <owner/repo#n>: rebuild the snapshot from the issue's freeze-data block
  local repo=${1%#*} n=${1##*#} body data
  printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || die 2 "--issue takes OWNER/REPO#N"
  case "$n" in ''|*[!0-9]*) die 2 "--issue takes OWNER/REPO#N" ;; esac
  body=$(gh api "repos/$repo/issues/$n" --jq .body 2>/dev/null) || die 4 "cannot read $repo#$n"
  data=$(printf '%s\n' "$body" | sed -n 's/^<!-- freeze-data \(.*\) -->$/\1/p' | head -1)
  [ -n "$data" ] || die 4 "$repo#$n holds no freeze data"
  printf '%s' "$data" | jq -c --arg r "$repo" --argjson n "$n" \
    '{id, created: null, mode: "hard", from_issue: true, records: [{repo: $r, issue: $n}],
      entries: [.entries[] | del(.resume) | . + {home: $r, recorded: true, from_issue: true,
        outcome: (if .local then "kept:local" elif .caller then "kept:caller" else "exited" end)}]}'
}

thaw_mark() { # thaw_mark <session id> <thaw outcome> [tty]
  snap_update --arg s "$1" --arg o "$2" --arg t "${3:-}" \
    '.entries |= map(if .session_id == $s then .thaw_outcome = $o | (if $t != "" then .thaw_tty = $t else . end) else . end)' ||
    note "snapshot not updated for $1"
}

cmd_thaw() {
  local id="" groups="[]" sids="[]" fromissue="" dry=0 live e sid tty line msg win out rc g left reopened=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --group) [ $# -ge 2 ] || die 2 "--group needs a name"; groups=$(printf '%s' "$groups" | jq -c --arg v "$2" '. + [$v]'); shift 2 ;;
      --issue) [ $# -ge 2 ] || die 2 "--issue needs OWNER/REPO#N"; fromissue=$2; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --continue) [ $# -ge 2 ] || die 2 "--continue needs a freeze id"; [ -z "$id" ] || die 2 "one freeze id only"; id=$2; shift 2 ;;
      -*) die 2 "thaw: unknown option '$1'" ;;
      latest|[0-9]*T[0-9]*Z) [ -z "$id" ] || die 2 "one freeze id only"; id=$1; shift ;;
      *) printf '%s' "$1" | grep -Eq '^[0-9a-fA-F-]{8,}$' || die 2 "thaw takes a freeze id, latest, or session ids ('$1')"
         sids=$(printf '%s' "$sids" | jq -c --arg v "$1" '. + [$v]'); shift ;;
    esac
  done
  need_helpers
  for g in $(printf '%s' "$groups" | jq -r '.[]'); do group_known "$g" || die 2 "unknown group '$g'"; done
  case "$id" in ''|latest)
    id=$(ls "$FREEZE_DIR" 2>/dev/null | sed -n 's/^\([0-9]\{8\}T[0-9]\{6\}Z\)\.json$/\1/p' | sort | tail -1)
    [ -n "$id" ] || [ -n "$fromissue" ] || die 4 "no freeze snapshot in $FREEZE_DIR" ;;
  esac
  [ "$dry" = 1 ] || freeze_lock
  mkdir -p "$FREEZE_DIR"
  if [ -n "$id" ] && [ -f "$FREEZE_DIR/$id.json" ] && [ -z "$fromissue" ]; then
    FID=$id; SNAP="$FREEZE_DIR/$id.json"
  elif [ -n "$fromissue" ]; then
    out=$(snapshot_from_issue "$fromissue") || exit $?
    FID=$(printf '%s' "$out" | jq -r .id)
    case "$FID" in *[!0-9A-Z]*|'') die 4 "the freeze data names no valid id" ;; esac
    if [ -f "$FREEZE_DIR/$FID.json" ]; then
      SNAP="$FREEZE_DIR/$FID.json"   # the local snapshot is fuller than the issue
    else
      SNAP="$FREEZE_DIR/$FID.json"; [ "$dry" = 1 ] && SNAP="$FREEZE_DIR/$FID.dry.json"
      printf '%s\n' "$out" > "$SNAP"
    fi
  else
    die 4 "no snapshot for freeze '$id' (give --issue OWNER/REPO#N to read it from its issue)"
  fi
  find_caller
  live=$(survey_json | jq -sc '[.[] | .session_id // empty]')
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    sid=$(printf '%s' "$e" | jq -r .session_id)
    [ "$(printf '%s' "$e" | jq -r '.thaw_outcome // ""')" = reopened ] && continue
    if printf '%s' "$e" | jq -e '.outcome == "kept:local"' >/dev/null; then
      echo "KEPT $sid: unmapped tab; its details are on the machine that froze it"; continue
    fi
    if ! printf '%s' "$e" | jq -e '.outcome == "exited" or .outcome == "kept:caller"' >/dev/null; then
      [ "$dry" = 1 ] || thaw_mark "$sid" skipped:not-closed
      echo "SKIP $sid: it was not closed ($(printf '%s' "$e" | jq -r .outcome))"; continue
    fi
    if printf '%s' "$live" | jq -e --arg s "$sid" 'index($s) != null' >/dev/null; then
      [ "$dry" = 1 ] || thaw_mark "$sid" skipped:live
      echo "SKIP $sid: it is live already"; continue
    fi
    if printf '%s' "$e" | jq -e '.from_issue' >/dev/null; then
      # never typed from the issue text: rebuilt from a checked session id, folder and profile
      if ! is_uuid "$sid" || ! printf '%s' "$e" | jq -r '.profile // ""' | grep -Eq '^[A-Za-z0-9._@-]*$'; then
        echo "SKIP $sid: the freeze data in the issue does not hold a valid session id or profile"; continue
      fi
      line=$(resume_line "$(printf '%s' "$e" | jq -r '.cwd // "."')" "" "$(printf '%s' "$e" | jq -r '.profile // ""')" "$sid") || line=""
    else
      line=$(printf '%s' "$e" | jq -r '.resume // empty')
    fi
    if [ -z "$line" ] || ! has_transcript "$(printf '%s' "$e" | jq -r '.profile_dir // empty')" "$sid"; then
      [ "$dry" = 1 ] || thaw_mark "$sid" skipped:no-transcript
      echo "SKIP $sid: its transcript is not on this machine; resume it where it is: ${line:-(no resume line)}"; continue
    fi
    msg=$(thaw_message "$e")
    g=$(printf '%s' "$e" | jq -r '.group // "general"')
    if [ "$dry" = 1 ]; then echo "PLAN $sid -> group $g: $line"; continue; fi
    if ! ( check_memory ) 2>/dev/null; then
      left=$(jq '[.entries[] | select((.outcome == "exited" or .outcome == "kept:caller") and (.thaw_outcome // "") != "reopened")] | length' "$SNAP")
      echo "STOPPED: memory is low or cannot be read; $reopened reopened, $left left; run 'term.sh thaw --continue $FID' later"
      thaw_record
      freeze_unlock; return 3
    fi
    thaw_reserve "$e" "$line"; rc=$?
    if [ "$rc" = 6 ]; then thaw_mark "$sid" queued:worker-cap; echo "QUEUED $sid: the worker cap is reached"; continue; fi
    [ "$rc" = 0 ] || { echo "SKIP $sid: the registry could not be written"; continue; }
    win=$(window_for_group "$g" "$(survey_json)")
    out=$( launch_tab "$sid" "$line $(shq "$msg")" "$sid" "$win" ) || {
      thaw_mark "$sid" failed:open; echo "FAILED $sid: the tab did not open"; continue; }
    tty=$(printf '%s' "$out" | awk '{ print $2 }')
    if [ "$win" = new ]; then
      cache_window "$g" "$(reg_read -r --arg s "$sid" '.[] | select(.session_id == $s) | .window // empty')" || note "window not cached"
    fi
    thaw_mark "$sid" reopened "$tty"
    reopened=$((reopened + 1))
    echo "REOPENED $sid $tty (group $g)"
  done <<EOF
$(jq -c --argjson g "$groups" --argjson s "$sids" --argjson order "$(groups_list | jq -R . | jq -sc .)" '
  [.entries[] | select(.session_id != null)
   | select(($g | length) == 0 or (.group as $x | $g | index($x)))
   | select(($s | length) == 0 or (.session_id as $x | any($s[]; . as $p | $x | startswith($p))))]
  | sort_by((.group // "general") as $x | ($order | index($x)) // 999) | .[]' "$SNAP")
EOF
  if [ "$dry" = 1 ]; then
    case "$SNAP" in *.dry.json) rm -f "${SNAP:?}" ;; esac
    return 0
  fi
  thaw_record
  freeze_unlock
  return 0
}

thaw_record() { # mark the reopened rows on each freeze issue; finish it when every closed session is reopened
  local rec repo issue all done tf
  tf="${FREEZE_DIR:?}/${FID:?}.thaw"
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    repo=$(printf '%s' "$rec" | jq -r .repo); issue=$(printf '%s' "$rec" | jq -r .issue)
    jq -r --arg r "$repo" '"Thaw of Freeze \(.id):", (.entries[] | select(.home == $r and .recorded) | "- \(.session_id): \(.thaw_outcome // .outcome)")' \
      "$SNAP" > "$tf"
    all=$(jq --arg r "$repo" '[.entries[] | select(.home == $r and .recorded and (.outcome == "exited" or .outcome == "kept:caller"))] | length' "$SNAP")
    done=$(jq --arg r "$repo" '[.entries[] | select(.home == $r and .recorded and (.thaw_outcome == "reopened" or .thaw_outcome == "skipped:live"))] | length' "$SNAP")
    if [ "$all" -gt 0 ] && [ "$done" = "$all" ]; then
      "$HOME_LOG" finish "$issue" --repo "$repo" --run-id "freeze-$FID" --text-file "$tf" >/dev/null 2>>"$FREEZE_DIR/$FID.log" ||
        note "could not finish $repo#$issue"
    else
      "$HOME_LOG" checkpoint "$issue" --repo "$repo" --run-id "freeze-$FID" --park --text-file "$tf" >/dev/null 2>>"$FREEZE_DIR/$FID.log" ||
        note "could not update $repo#$issue"
    fi
    rm -f "$tf"
  done <<EOF
$(jq -c '.records[]' "$SNAP")
EOF
}
