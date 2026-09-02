#!/usr/bin/env bash
# Read a qsyn_xlr log and decide whether the synthesis is acceptable.
#
#   check_synth.sh <qsyn.txt> [more logs...]
#
# exit 0  clean, or only warnings already on the reviewed list
# exit 1  MUST FIX  - latch, combinational loop, undriven net, stuck pin, error
# exit 2  UNREVIEWED warnings - not known-good, not known-bad. A human decides once.
#
# WHY THIS EXISTS
#   qsyn_xlr exits 0 even when it fails (check_report() calls a bare exit()), so $? is
#   worthless. And an inferred latch does not stop the build - it silently turns
#   combinational logic into a transparent latch, which simulates fine, synthesises
#   fine, and then behaves differently on the board. It is the single most likely way
#   to get an RTL change that passes simulation and fails in fabric.
#
# It matches on Quartus's ENGLISH TEXT rather than message numbers. The numbers are
# easy to misremember; the wording has been stable for years. Message IDs are printed
# when present so you can look one up.
set -u
[ $# -ge 1 ] || { echo "usage: check_synth.sh <qsyn.txt> [more...]"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
SEEN="$HERE/reviewed_warnings.txt"      # one grep -F pattern per line, # comments ok
LOGS=("$@")
for f in "${LOGS[@]}"; do [ -r "$f" ] || { echo "STOP: cannot read $f"; exit 2; }; done

cat_logs() { cat "${LOGS[@]}" 2>/dev/null | tr -d '\r'; }
hits()     { cat_logs | grep -iE "$1" || true; }
count()    { hits "$1" | wc -l | tr -d ' '; }

echo "=== synthesis review: ${LOGS[*]} ==="
FAIL=0

# ---------------------------------------------------------------- hard failures
# Ordered by how badly each one bites us specifically.
# SUPPRESSIBLE says whether a line matching reviewed_warnings.txt may be waived.
# Latches, combinational loops and errors are NEVER waivable, however well understood:
# they change behaviour silently. "Stuck at GND" on the synthesis-only test wrapper is
# both expected and on the tool's own ignore list, so that one is reviewable.
declare -a NAME PAT WHY SUPPRESSIBLE
NAME+=("INFERRED LATCH");      PAT+=("inferring latch|inferred latch|latch is inferred"); SUPPRESSIBLE+=(no)
WHY+=("An always_comb path does not assign the variable on every branch, so Quartus builds a
     transparent latch. Simulation still looks right. On the board the value holds when you
     expect it to update. FIX: assign a default at the top of the block, or complete the
     if/case. Never fix it by adding a clock.")

NAME+=("COMBINATIONAL LOOP");  PAT+=("combinational loop|found combinational loop"); SUPPRESSIBLE+=(no)
WHY+=("Logic feeds itself with no register. Timing analysis cannot bound it and F_max
     becomes meaningless. FIX: break the loop with a register, or find the accidental
     self-reference - usually a variable read and written in the same always_comb.")

NAME+=("UNDRIVEN / UNASSIGNED"); PAT+=("has no driver|never assigned|no driver.*net|is stuck at"); SUPPRESSIBLE+=(yes)
WHY+=("A signal reads as GND/VCC regardless of the design. Usually a typo in a name, or a
     port left unconnected. Whatever logic depended on it is gone.")

NAME+=("ERROR");               PAT+=("^ *Error \(|^Error:"); SUPPRESSIBLE+=(no)
WHY+=("Synthesis did not succeed. qsyn_xlr still exits 0 - do not trust the exit code.")

reviewed_filter() {   # drop lines matching a recorded pattern
  if [ -r "$SEEN" ]; then grep -vFf <(grep -vE '^\s*(#|$)' "$SEEN") || true; else cat; fi
}
for i in "${!NAME[@]}"; do
  if [ "${SUPPRESSIBLE[$i]}" = yes ]; then
    H=$(hits "${PAT[$i]}" | reviewed_filter)
  else
    H=$(hits "${PAT[$i]}")
  fi
  n=$(printf '%s' "$H" | grep -c . || true)
  if [ "$n" != 0 ]; then
    FAIL=1
    echo
    echo "!!! ${NAME[$i]}  ($n line(s))  -- MUST FIX"
    printf '%s\n' "$H" | sed 's/^[[:space:]]*/    /' | head -12
    echo "${WHY[$i]}" | sed 's/^ */    /'
    [ "${SUPPRESSIBLE[$i]}" = no ] && echo "    This category can NOT be waived in reviewed_warnings.txt."
  fi
done

# ---------------------------------------------------------------- every other warning
# Nothing is allowed to be silently ignored. A warning is either fixed, or written into
# reviewed_warnings.txt with a reason. That file is the record of what we decided to live
# with, and it is reviewed when it grows.
ALLW=$(cat_logs | grep -E "^ *(Warning|Critical Warning) \(" | sed 's/^[[:space:]]*//' | sort -u)
TOTAL=$(printf '%s' "$ALLW" | grep -c . || true)

if [ -r "$SEEN" ]; then
  NEW=$(printf '%s\n' "$ALLW" | grep -vFf <(grep -vE '^\s*(#|$)' "$SEEN") || true)
else
  NEW="$ALLW"
fi
NEWN=$(printf '%s' "$NEW" | grep -c . || true)

echo
echo "warnings: $TOTAL distinct, $NEWN unreviewed"
if [ "$NEWN" != 0 ]; then
  echo
  echo "--- UNREVIEWED - decide once, then record ---"
  printf '%s\n' "$NEW" | head -25 | sed 's/^/    /'
  echo
  echo "    For each: fix the RTL, or append a grep -F pattern plus a one-line reason to"
  echo "    $SEEN"
  echo "    Do not add a pattern so broad it would also hide a latch."
  [ "$FAIL" = 0 ] && FAIL=2
fi

# ---------------------------------------------------------------- the report line
LAT=$(count "inferring latch|inferred latch")
LOOP=$(count "combinational loop")
ERR=$(count "^ *Error \(|^Error:")
echo
echo "REPORT.md synthesis line:"
echo "  synthesis  $ERR errors · $LAT latches · $LOOP combinational loops · $NEWN unreviewed warnings"

echo
case $FAIL in
  0) echo "RESULT: clean." ;;
  1) echo "RESULT: MUST FIX. Do not measure, do not publish a release - a latch makes the"
     echo "        fabric behave differently from the simulation you are about to trust." ;;
  2) echo "RESULT: unreviewed warnings. Read them, then fix or record. Not automatic." ;;
esac
exit $FAIL
