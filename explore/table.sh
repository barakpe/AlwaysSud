#!/bin/bash
# Regenerate every cycle table in EXPLORATION.md from the model.
# Cycles here are SOLVER-FSM cycles. The measured "Sudoku solve" window is
# +186..+200 on top (wrapper STORE + the RISC-V poll loop); see EXPLORATION.md.
cd "$(dirname "$0")/.." || exit 2
A="v0 m1 s0 s1 s2 s2u m2 s2m s2um p1 p2 p3 p4"
echo "== the four repo boards (classic) =="
printf "%-6s %10s %10s %10s %14s\n" arch easy1 20blanks 51blanks hard1
for a in $A; do
  r=""
  for b in easy1 20blanks 51blanks hard1; do
    r="$r $(explore/model/arch $a sw/apps/sud_shared/sudoku_input_$b.txt --quiet | cut -f3)"
  done
  printf "%-6s %10s %10s %10s %14s\n" $a $r
done
echo
echo "== held-out sets: WORST CASE, then p99 / median =="
printf "%-6s %-24s %14s %12s %10s %6s\n" arch set WORST p99 median n
for s in "ho_published classic" "gen_classic_min classic" "gen_classic_easy classic" \
         "gen_diagonal_min diagonal" "gen_diagonal_easy diagonal" "gen_windoku_min windoku"; do
  set -- $s
  for a in $A; do
    o=$(explore/model/arch $a --list explore/puzzles/$1.txt --variant $2 --quiet 2>/dev/null)
    printf "%-6s %-24s %14s %12s %10s %6s\n" $a "$1" \
      "$(echo "$o" | grep -oE 'MAX=[0-9]+' | cut -d= -f2)" \
      "$(echo "$o" | grep -oE 'p99=[0-9]+' | cut -d= -f2)" \
      "$(echo "$o" | grep -oE 'med=[0-9]+' | cut -d= -f2)" \
      "$(echo "$o" | grep -oE 'n=[0-9]+'   | cut -d= -f2)"
  done
done
