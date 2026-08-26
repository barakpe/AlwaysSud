#!/usr/bin/env bash
# CLOUD side: synthesise, simulate the three simulatable boards, verify, report.
# Usage: bench/measure_sim.sh <tag>
#
# FIRST CUT - written from the plan, not from experience. The first v0 pass is
# meant to be done by hand; fix this script from what that pass teaches.
set -u
TAG="${1:?usage: measure_sim.sh <tag>}"
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT="$REPO/logs/$TAG"; mkdir -p "$OUT"
XLR=alwaysud

echo "=== 1. synthesis ==="
( cd "$MY_K5_XLRS/$XLR" && qsyn_xlr $XLR -all ) 2>&1 | tee "$OUT/qsyn.txt"
grep -E "Logic Elements|memory registers|Max FPGA Frequency|errors" "$OUT/qsyn.txt" || true
grep -qE "0 +errors" "$OUT/qsyn.txt" || { echo "SYNTHESIS ERRORS - stopping"; exit 1; }

echo "=== 2. simulation ==="
for B in easy1 20blanks 51blanks; do
  echo "--- $B ---"
  ( set_k5_terminal; launch_k5_sim $XLR ) > "$OUT/sim_$B.sim.txt" 2>&1 &
  SIM=$!
  sleep 2
  ( set_k5_terminal; launch_k5_app $XLR -asl sud_shared -gpv $B ) > "$OUT/sim_$B.txt" 2>&1
  wait $SIM 2>/dev/null || true
  grep -E "Sudoku solve" "$OUT/sim_$B.txt" || echo "  no cycle count!"
  python "$REPO/bench/solve_ref.py" --check $B "$OUT/sim_$B.txt" || exit 1
done

echo
echo "=== summary: $TAG ==="
for B in easy1 20blanks 51blanks; do
  printf "%-10s %s\n" "$B" "$(grep -oE 'Sudoku solve +[0-9,]+' "$OUT/sim_$B.txt" | grep -oE '[0-9,]+$')"
done
echo
echo "enums md5: $(md5sum "$REPO/sw/apps/$XLR/${XLR}_enums.svh" | cut -d' ' -f1)"
echo "Next: comp_fpga $XLR, then write the handoff block (docs/HANDOFF.md)."
