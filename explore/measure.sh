#!/bin/bash
# One exploration data point: stage explore/exp/<name>/ as the accelerator,
# synthesise it standalone, review the warnings, optionally simulate.
#
# Same platform rules as .claude/skills/cloud-measure (aliases, qsyn exits 0 on
# failure, -fit/-sta alone are broken, no clock constraint so slack is fiction).
# Differences, both deliberate:
#   - no F_max floor. SKILL.md removed it 2026-09-02; measure_cloud.sh still has
#     the old FMAX_MIN=56.45 die() and would refuse to record a slow-but-real
#     data point, which during exploration is exactly the number I want.
#   - LE budget is the device's ~50k, warning at the 20k documented limit,
#     because a direction that needs 25k LE is a finding, not a build error.
NAME="$1"; shift                       # capture BEFORE sourcing (k5_env.sh)
ARGS="$*"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$REPO/.claude/skills/cloud-measure/k5_env.sh"

XLR=alwaysud
EXP="$REPO/explore/exp/$NAME"
OUT="$REPO/logs/explore-$NAME/sim"
[ -d "$EXP" ] || { echo "no such experiment: $EXP"; exit 2; }
mkdir -p "$OUT"
die() { echo; echo "########## STOP: $* ##########"; exit 1; }

echo "===== 1. stage $NAME ====="
rm -rf "$MY_K5_PROJ/hw/xlrs/$XLR" "$MY_K5_PROJ/sw/apps/$XLR" "$MY_K5_PROJ/sw/apps/sud_shared"
mkdir -p "$MY_K5_PROJ/hw/xlrs/$XLR"
cp "$EXP"/* "$MY_K5_PROJ/hw/xlrs/$XLR/" || die "staging hw failed"
cp -r "$REPO/sw/apps/$XLR"       "$MY_K5_PROJ/sw/apps/" || die "staging sw failed"
cp -r "$REPO/sw/apps/sud_shared" "$MY_K5_PROJ/sw/apps/" || die "staging sud_shared failed"
ls "$MY_K5_PROJ/hw/xlrs/$XLR"

echo; echo "===== 2. synthesis (qsyn_xlr -all, ~4.5 min) ====="
( cd "$MY_K5_XLRS/$XLR" && qsyn_xlr $XLR -all ) 2>&1 | tee "$OUT/qsyn.txt" | tail -25
mkdir -p "$OUT/qsyn_output_files"
cp -a "$MY_K5_XLRS/$XLR/qsyn_output_files/." "$OUT/qsyn_output_files/" 2>/dev/null

grep -qE '^ERROR ' "$OUT/qsyn.txt"                     && die "qsyn_xlr reported ERROR"
grep -qiE 'Forbidden inferred latches' "$OUT/qsyn.txt" && die "inferred latches"
grep -qiE 'Forbidden combinatorial'    "$OUT/qsyn.txt" && die "combinational loops"
[ "$(grep -c 'was successful' "$OUT/qsyn.txt")" -eq 3 ] || die "syn/fit/sta did not all succeed"

LE=$(grep 'Total FPGA Logic Elements' "$OUT/qsyn.txt" | sed 's/.*: *//' | tr -dc '0-9')
REGS=$(grep 'Total FPGA memory registers' "$OUT/qsyn.txt" | sed 's/.*: *//' | tr -dc '0-9')
MEMB=$(grep 'Total FPGA memory bits' "$OUT/qsyn.txt" | sed 's/.*: *//' | tr -dc '0-9')
FMAX=$(grep 'Max FPGA Frequency' "$OUT/qsyn.txt" | awk '{print $4}')
LE_FIT=$(awk -F'[:/]' '/Total logic elements/{gsub(/[^0-9]/,"",$2); print $2; exit}' \
         "$OUT/qsyn_output_files/${XLR}.fit.summary" 2>/dev/null)
echo "RESULT $NAME: LEs(map)=$LE LEs(fit)=$LE_FIT regs=$REGS membits=$MEMB F_max=$FMAX MHz" \
  | tee "$OUT/RESULT.txt"
[ -n "$LE" ] && [ -n "$FMAX" ] || die "could not parse LE / F_max"
[ "$LE" -lt 45000 ] || die "logic elements $LE >= device budget"
[ "$LE" -lt 20000 ] || echo "NOTE: $LE LE is over the 20,000 limit in docs/MEASUREMENT.md"

echo; echo "===== 3. warning review ====="
bash "$REPO/.claude/skills/cloud-measure/check_synth.sh" "$OUT/qsyn.txt" | tee "$OUT/check_synth.txt" | tail -20
CS=${PIPESTATUS[0]}
[ "$CS" -eq 1 ] && die "check_synth.sh says MUST FIX"

case "$ARGS" in *--sim*)
  echo; echo "===== 4. simulation ====="
  for B in easy1 20blanks 51blanks; do
    "$REPO/.claude/skills/cloud-measure/sim_board.sh" "$B" "$OUT" || die "sim $B failed"
  done
  echo; echo "===== 5. correctness gate ====="
  BAD=""
  for B in easy1 20blanks 51blanks; do
    python3 "$REPO/bench/solve_ref.py" --check "$B" "$OUT/sim_$B.txt" 2>&1 | tee -a "$OUT/gate.txt"
    [ "${PIPESTATUS[0]}" -eq 0 ] || BAD="$BAD $B"
  done
  echo; echo "===== 6. cycles ====="
  cyc() { grep -oE "$1 +[0-9,]+" "$2" | grep -oE '[0-9,]+$' | tail -1; }
  for B in easy1 20blanks 51blanks; do
    printf "%-10s setup+load %-8s solve %-12s total %s\n" "$B" \
      "$(cyc 'Board setup\+load' "$OUT/sim_$B.txt")" \
      "$(cyc 'Sudoku solve'      "$OUT/sim_$B.txt")" \
      "$(cyc 'Total'             "$OUT/sim_$B.txt")"
  done | tee "$OUT/cycles.txt"
  [ -z "$BAD" ] || die "correctness MISMATCH on:$BAD"
  ;;
esac
echo; echo "Logs: $OUT"
