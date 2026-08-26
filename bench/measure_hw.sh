#!/usr/bin/env bash
# LAPTOP side: program the board, run all four boards, verify, report.
# Usage: bench/measure_hw.sh <tag> [expected-enums-md5]
#
# FIRST CUT - see the note in measure_sim.sh.
set -u
TAG="${1:?usage: measure_hw.sh <tag> [enums-md5]}"
WANT_MD5="${2:-}"
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT="$REPO/logs/$TAG"; mkdir -p "$OUT"
XLR=alwaysud

HAVE_MD5=$(md5sum "$K5_SW_APPS/$XLR/${XLR}_enums.svh" | cut -d' ' -f1)
echo "enums md5 on this machine: $HAVE_MD5"
if [ -n "$WANT_MD5" ] && [ "$HAVE_MD5" != "$WANT_MD5" ]; then
  echo "REFUSING TO RUN: enums md5 does not match the handoff ($WANT_MD5)."
  echo "A stale .svh against a fresh .sof compiles clean and misbehaves at runtime."
  exit 1
fi

echo "=== programming the board ==="
set_k5_terminal
prog_fpga $XLR 2>&1 | tee "$OUT/prog.txt"

for B in easy1 20blanks 51blanks hard1; do
  echo "--- $B ---"
  launch_k5_app $XLR -asl sud_shared -gpv $B > "$OUT/hw_$B.txt" 2>&1
  grep -E "Sudoku solve" "$OUT/hw_$B.txt" || echo "  no cycle count!"
  python "$REPO/bench/solve_ref.py" --check $B "$OUT/hw_$B.txt" || echo "  CORRECTNESS FAIL"
done

echo
echo "=== summary: $TAG (hardware) ==="
for B in easy1 20blanks 51blanks hard1; do
  printf "%-10s %s\n" "$B" "$(grep -oE 'Sudoku solve +[0-9,]+' "$OUT/hw_$B.txt" | grep -oE '[0-9,]+$')"
done
echo
echo "hard1 is the score. Compare the other three against the simulation numbers -"
echo "they should match EXACTLY. A mismatch is a red flag, not rounding."
