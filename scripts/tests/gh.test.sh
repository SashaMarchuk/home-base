#!/bin/bash
# Tests for the porcelain issue verbs of the gh stub (stubs/gh): gh issue create|list|view|comment|close|reopen|edit.
# They must share state with the `gh api` routes. Exit 0 when all pass.
# No script here calls these verbs; they are kept because eval harnesses outside this repo copy the stub, so this file is their only proof.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/gh-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
export PATH="$ROOT/scripts/tests/stubs:$PATH" GH_STUB_DIR="$T/ghstore"
unset GH_REPO GH_CONFIG_DIR
FAILN=0
bad() { FAILN=$((FAILN + 1)); echo "FAIL: $*"; }
eq() { [ "$2" = "$3" ] || bad "$1: got '$2', want '$3'"; }
R="-R test/gh"

# repo resolution
gh issue list >/dev/null 2>"$T/err" && bad "no repo must fail"
grep -q 'no repository' "$T/err" || bad "no repo message: $(cat "$T/err")"
eq "unknown flag" "$(gh issue list $R --bogus 2>&1; echo $?)" "gh stub: unsupported flag --bogus
1"

# create
eq "create prints url" "$(gh issue create $R -t "First" -b "alpha body" -l a,b --label c -a me)" "https://github.com/test/gh/issues/1"
printf 'from file\n' > "$T/body"
eq "create from file, GH_REPO" "$(GH_REPO=test/gh gh issue create --title Second --body-file "$T/body")" "https://github.com/test/gh/issues/2"
eq "create from stdin" "$(echo stdin-body | gh issue create $R -t Third -F -)" "https://github.com/test/gh/issues/3"
eq "api sees porcelain issue" "$(gh api repos/test/gh/issues/1 --jq '[.labels[].name]|join(",")')" "a,b,c"
eq "counter shared with api" "$(gh api repos/test/gh/issues -f title=Fourth --jq .number)" "4"
eq "label registry" "$(gh api repos/test/gh/labels --jq 'map(.name)|join(",")')" "a,b,c"

# list
eq "list newest first" "$(gh issue list $R --json number --jq 'map(.number)|join(",")')" "4,3,2,1"
eq "list label filter" "$(gh issue list $R -l a -l b --json number --jq '.[].number')" "1"
eq "list search" "$(gh issue list $R -S ALPHA --json title --jq '.[].title')" "First"
eq "list limit" "$(gh issue list $R -L 2 --json number --jq length)" "2"
gh issue list $R -L 1 | awk -F'\t' '$1==4&&$2=="OPEN"&&$3=="Fourth"{f=1} END{exit !f}' || bad "plain list line"
eq "list shapes" "$(gh issue list $R -l c --json labels,author,url,state --jq '.[0]|"\(.labels[0].name) \(.author.login) \(.url) \(.state)"')" "a owner https://github.com/test/gh/issues/1 OPEN"
gh issue list $R --json nope >/dev/null 2>&1 && bad "unknown json field must fail"

# comment
eq "comment url" "$(gh issue comment 1 $R -b "hi")" "https://github.com/test/gh/issues/1#issuecomment-1"
eq "comment edit-last" "$(gh issue comment https://github.com/test/gh/issues/1 --edit-last -b "hi2")" "https://github.com/test/gh/issues/1#issuecomment-1"
eq "comment via api" "$(gh api repos/test/gh/issues/1/comments --jq 'map(.body)|join(",")')" "hi2"
eq "view comments json" "$(gh issue view 1 $R --json comments --jq '.comments[0]|"\(.body) \(.author.login)"')" "hi2 owner"
gh issue comment 2 $R --edit-last -b x >/dev/null 2>&1 && bad "edit-last without a comment must fail"

# view
gh issue view 1 $R > "$T/v"
grep -qx "title:	First" "$T/v" && grep -qx "state:	OPEN" "$T/v" && grep -qx "labels:	a, b, c" "$T/v" && grep -qx "number:	1" "$T/v" && grep -qx "alpha body" "$T/v" || bad "plain view: $(cat "$T/v")"
gh issue view 1 $R --comments | grep -qx hi2 || bad "view --comments"
gh issue view 99 $R >/dev/null 2>&1 && bad "view missing must fail"

# close / reopen
gh issue close 2 $R -c "bye" -r "not planned" 2>/dev/null || bad "close"
eq "closed via api" "$(gh api repos/test/gh/issues/2 --jq '"\(.state) \(.state_reason) \(.comments)"')" "closed not_planned 1"
eq "closed json" "$(gh issue view 2 $R --json state,stateReason,closedAt --jq '"\(.state) \(.stateReason) \(.closedAt != null)"')" "CLOSED NOT_PLANNED true"
eq "list closed" "$(gh issue list $R -s closed --json number --jq '.[].number')" "2"
eq "list all" "$(gh issue list $R -s all --json number --jq length)" "4"
gh issue reopen 2 $R 2>/dev/null || bad "reopen"
eq "reopened" "$(gh api repos/test/gh/issues/2 --jq '"\(.state) \(.closed_at)"')" "open null"

# edit
eq "edit url" "$(gh issue edit 3 $R --title T3 -b nb --add-label x,y --remove-label nothere)" "https://github.com/test/gh/issues/3"
gh issue edit 3 $R --remove-label x >/dev/null
eq "edit applied" "$(gh api repos/test/gh/issues/3 --jq '"\(.title) \(.body) \([.labels[].name]|join(","))"')" "T3 nb y"

# every call is logged
[ "$(wc -l < "$GH_STUB_DIR/calls.log")" -gt 30 ] || bad "calls must be logged"

[ "$FAILN" = 0 ]
