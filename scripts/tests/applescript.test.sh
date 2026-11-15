#!/usr/bin/env bash
# Every AppleScript in the terminal helpers compiles (osacompile only compiles, nothing runs).
# The fake backend never runs osascript, so a syntax error would otherwise first show on a real tab.
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd -P)
command -v osacompile >/dev/null 2>&1 || { echo "applescript.test: osacompile not found, skipped"; exit 0; }
PASS=0; FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/applescript-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
compiles() { osacompile -o "$T/out.scpt" "$1" >/dev/null 2>&1; }
# split every <<'OSA...' heredoc and every osascript -e '...' of a file into files under $T/<name>/
extract() { # extract <file> <dir>
  mkdir -p "$2"
  python3 - "$1" "$2" <<'PY'
import re, sys
s = open(sys.argv[1]).read(); n = 0
for m in re.finditer(r"<<'?(OSA\w*)'?[^\n]*\n(.*?)\n\1\n", s, re.S):
    n += 1; open(f"{sys.argv[2]}/{n}.applescript", "w").write(m.group(2))
for m in re.finditer(r"osascript -e '([^']*)'", s):
    n += 1; open(f"{sys.argv[2]}/{n}.applescript", "w").write(m.group(1))
print(n)
PY
}
for f in "$SRC"/scripts/term/*.sh; do
  d="$T/$(basename "$f")"; n=$(extract "$f" "$d")
  for s in "$d"/*.applescript; do
    [ -f "$s" ] || continue
    if compiles "$s"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $(basename "$f"): block $(basename "$s") does not compile"; fi
  done
done
# the scripts holding them parse under the system bash (a quote inside a heredoc in $(...) breaks bash 3.2)
for f in "$SRC"/scripts/term/*.sh; do
  if /bin/bash -n "$f" 2>/dev/null; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $(basename "$f") does not parse under /bin/bash"; fi
done
[ "$PASS" -ge 5 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL fewer AppleScript blocks found than expected ($PASS)"; }
# must fail: a reserved word used as a variable name (the bug that broke "open" on a real tab)
printf 'on run argv\n  set where to item 1 of argv\nend run\n' > "$T/bad.applescript"
if compiles "$T/bad.applescript"; then FAIL=$((FAIL + 1)); echo "FAIL a reserved-word variable compiled"; else PASS=$((PASS + 1)); fi
echo "applescript.test: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
