#!/bin/bash
# Stage explore/exp/<name>/ and run ONLY the K5 simulation + correctness gate.
# Separate from measure.sh because a 25k-LE fit takes ~2.5 h and the end-to-end
# integration question (does it work behind the real wrapper, and what does the
# measured window cost on top of the solver FSM?) does not need the fitter.
NAME="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
source "$REPO/.claude/skills/cloud-measure/k5_env.sh"
XLR=alwaysud; EXP="$REPO/explore/exp/$NAME"; OUT="$REPO/logs/explore-$NAME/sim"
[ -d "$EXP" ] || { echo "no such experiment: $EXP"; exit 2; }
mkdir -p "$OUT"
rm -rf "$MY_K5_PROJ/hw/xlrs/$XLR" "$MY_K5_PROJ/sw/apps/$XLR" "$MY_K5_PROJ/sw/apps/sud_shared"
mkdir -p "$MY_K5_PROJ/hw/xlrs/$XLR"
cp "$EXP"/* "$MY_K5_PROJ/hw/xlrs/$XLR/" || exit 1
cp -r "$REPO/sw/apps/$XLR" "$REPO/sw/apps/sud_shared" "$MY_K5_PROJ/sw/apps/" || exit 1
for B in easy1 20blanks 51blanks; do
  "$REPO/.claude/skills/cloud-measure/sim_board.sh" "$B" "$OUT" || { echo "SIM FAIL $B"; exit 1; }
done
echo; echo "===== correctness gate ====="
BAD=""
for B in easy1 20blanks 51blanks; do
  python3 "$REPO/bench/solve_ref.py" --check "$B" "$OUT/sim_$B.txt" 2>&1 | tee -a "$OUT/gate.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || BAD="$BAD $B"
done
echo; echo "===== cycles ====="
cyc() { grep -oE "$1 +[0-9,]+" "$2" | grep -oE '[0-9,]+$' | tail -1; }
for B in easy1 20blanks 51blanks; do
  printf "%-10s setup+load %-8s solve %-12s total %s\n" "$B" \
    "$(cyc 'Board setup\+load' "$OUT/sim_$B.txt")" "$(cyc 'Sudoku solve' "$OUT/sim_$B.txt")" \
    "$(cyc 'Total' "$OUT/sim_$B.txt")"
done | tee "$OUT/cycles.txt"
[ -z "$BAD" ] && echo "GATE: all PASS" || { echo "GATE FAIL:$BAD"; exit 1; }
