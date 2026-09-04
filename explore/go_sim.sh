#!/bin/bash
# Run the K5 end-to-end simulation against WHATEVER IS ALREADY STAGED - no re-staging,
# because a quartus_fit is reading that directory. sim_board.sh compiles from the .f
# with xrun; it does not touch qsyn_output_files.
R=/project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud
O=$R/logs/explore-s2fast/sim
for B in easy1 20blanks 51blanks; do
  "$R/.claude/skills/cloud-measure/sim_board.sh" "$B" "$O" || { echo "SIM FAIL $B"; exit 1; }
done
echo "===== correctness gate ====="
for B in easy1 20blanks 51blanks; do
  python3 "$R/bench/solve_ref.py" --check "$B" "$O/sim_$B.txt"
done
echo "===== cycles ====="
cyc() { grep -oE "$1 +[0-9,]+" "$2" | grep -oE '[0-9,]+$' | tail -1; }
for B in easy1 20blanks 51blanks; do
  printf "%-10s setup+load %-8s solve %-10s total %s\n" "$B" \
    "$(cyc 'Board setup\+load' "$O/sim_$B.txt")" "$(cyc 'Sudoku solve' "$O/sim_$B.txt")" \
    "$(cyc 'Total' "$O/sim_$B.txt")"
done
echo GO_SIM_DONE
