#!/bin/bash
# Cloud half of one AlwaysSud iteration.  Usage: measure_cloud.sh <tag> [--with-fpga]
#
# Mechanical steps only: stage -> synthesise -> simulate 3 boards -> correctness gate
# -> (optional) bitstream -> handoff block.  Stops loudly on any gate failure.
# It NEVER runs git.  Judgement calls stay with the human - see SKILL.md.
TAG="$1"; WITH_FPGA="$2"                    # capture BEFORE sourcing (k5_env.sh)
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/k5_env.sh"
REPO="$(cd "$HERE/../../.." && pwd)"

[ -n "$TAG" ] || { echo "usage: measure_cloud.sh <tag> [--with-fpga]"; exit 2; }
OUT="$REPO/logs/$TAG"; mkdir -p "$OUT"
XLR=alwaysud
LE_LIMIT=20000
FMAX_MIN=56.45
BOARDS="easy1 20blanks 51blanks"            # hard1 is HARDWARE ONLY (~30 h in RTL)

die() { echo; echo "########## STOP: $* ##########"; exit 1; }

#--------------------------------------------------------------- 1. stage
echo "===== 1. stage ====="
# cp -r MERGES into an existing tree, so delete the target dirs first.
# NOTE: this also deletes qsyn_output_files/ under hw/xlrs/$XLR - that is why
# step 2 archives the reports into logs/<tag>/ before anything can re-stage.
rm -rf "$MY_K5_PROJ/hw/xlrs/$XLR" "$MY_K5_PROJ/sw/apps/$XLR" "$MY_K5_PROJ/sw/apps/sud_shared"
cp -r "$REPO/hw/xlrs/$XLR"        "$MY_K5_PROJ/hw/xlrs/"   || die "staging hw failed"
cp -r "$REPO/sw/apps/$XLR"        "$MY_K5_PROJ/sw/apps/"   || die "staging sw failed"
cp -r "$REPO/sw/apps/sud_shared"  "$MY_K5_PROJ/sw/apps/"   || die "staging sud_shared failed"
ENUMS_MD5=$(md5sum "$MY_K5_PROJ/sw/apps/$XLR/${XLR}_enums.svh" | cut -d' ' -f1)
echo "enums md5: $ENUMS_MD5"

#--------------------------------------------------------------- 2. synthesis
echo; echo "===== 2. synthesis (qsyn_xlr -all, ~4.5 min) ====="
# -fit and -sta ALONE DO NOT WORK: qsyn_xlr.py:196 runs `rm -r -f *db*` on every
# invocation, deleting the synthesis database the fitter needs. Only -syn and -all
# are usable. And qsyn_xlr EXITS 0 EVEN WHEN IT FAILS, so parse stdout, not $?.
( cd "$MY_K5_XLRS/$XLR" && qsyn_xlr $XLR -all ) 2>&1 | tee "$OUT/qsyn.txt"
mkdir -p "$OUT/qsyn_output_files"
cp -a "$MY_K5_XLRS/$XLR/qsyn_output_files/." "$OUT/qsyn_output_files/" 2>/dev/null

grep -qE '^ERROR ' "$OUT/qsyn.txt"                    && die "qsyn_xlr reported ERROR (see $OUT/qsyn.txt)"
grep -qiE 'Forbidden inferred latches'  "$OUT/qsyn.txt" && die "inferred latches"
grep -qiE 'Forbidden combinatorial'     "$OUT/qsyn.txt" && die "combinational loops"
[ "$(grep -c 'was successful' "$OUT/qsyn.txt")" -eq 3 ] || die "syn/fit/sta did not all succeed"
grep -E '[1-9][0-9]* +errors' "$OUT/qsyn.txt"         && die "non-zero error count"

LE=$(grep 'Total FPGA Logic Elements' "$OUT/qsyn.txt" | tr -dc '0-9')
REGS=$(grep 'Total FPGA memory registers' "$OUT/qsyn.txt" | tr -dc '0-9')
FMAX=$(grep 'Max FPGA Frequency' "$OUT/qsyn.txt" | awk '{print $4}')
# The headline LE is the Analysis&Synthesis estimate. The fitter's number is what
# actually lands on the device; record both, they differ (9,393 vs 8,967 at v0).
LE_FIT=$(awk -F'[:/]' '/Total logic elements/{gsub(/[^0-9]/,"",$2); print $2; exit}' "$OUT/qsyn_output_files/${XLR}.fit.summary" 2>/dev/null)
echo "LEs(map)=$LE  LEs(fit)=$LE_FIT  regs=$REGS  F_max=$FMAX MHz"

[ -n "$LE" ] && [ -n "$FMAX" ] || die "could not parse LE / F_max out of $OUT/qsyn.txt"
[ "$LE" -lt "$LE_LIMIT" ] || die "logic elements $LE >= limit $LE_LIMIT"
awk -v f="$FMAX" -v m="$FMAX_MIN" 'BEGIN{exit !(f>=m)}' || die "F_max $FMAX MHz < required $FMAX_MIN MHz"

#--------------------------------------------------------------- 3. simulation
echo; echo "===== 3. simulation ====="
for B in $BOARDS; do
  "$HERE/sim_board.sh" "$B" "$OUT" || die "simulation of $B failed"
done

#--------------------------------------------------------------- 4. correctness gate
echo; echo "===== 4. correctness gate (BEFORE any timing number counts) ====="
FAILED=""
for B in $BOARDS; do
  python3 "$REPO/bench/solve_ref.py" --check "$B" "$OUT/sim_$B.txt" || FAILED="$FAILED $B"
done
[ -z "$FAILED" ] || die "correctness MISMATCH on:$FAILED - a faster wrong answer is not a result"

#--------------------------------------------------------------- 5. cycles
# Since 2026-08-29 the app prints THREE performance lines, because solve() ends the
# setup window before calling the solver:
#   "Board setup+load"  board LOAD over 3 bursts + both register handshakes
#   "Sudoku solve"      the search alone   <-- this is the metric
#   "Total"             setup+solve, i.e. the single number printed before the split
cyc() { grep -oE "$1 +[0-9,]+" "$2" | grep -oE '[0-9,]+$' | tail -1; }
echo; echo "===== 5. cycles ====="
printf "%-10s %12s %12s %12s\n" board setup+load solve total | tee "$OUT/cycles.txt"
for B in $BOARDS; do
  printf "%-10s %12s %12s %12s\n" "$B" \
    "$(cyc 'Board setup\+load' "$OUT/sim_$B.txt")" \
    "$(cyc 'Sudoku solve'       "$OUT/sim_$B.txt")" \
    "$(cyc 'Total'              "$OUT/sim_$B.txt")"
done | tee -a "$OUT/cycles.txt"

#--------------------------------------------------------------- 6. bitstream
SYS_LE="(not built)"; SYS_FMAX="(not built)"; SYS_MEMBITS="(not built)"
if [ "$WITH_FPGA" = "--with-fpga" ]; then
  echo; echo "===== 6. comp_fpga (TAKES OVER TEN MINUTES) ====="
  ( cd "$MY_K5_PROJ/hw/gen_fpga" && comp_fpga $XLR ) 2>&1 | tee "$OUT/comp_fpga.txt"
  grep -qE '^ERROR |Something went wrong' "$OUT/comp_fpga.txt" && die "comp_fpga failed"
  mkdir -p "$OUT/output_files"
  cp -a "$MY_K5_PROJ/hw/gen_fpga/output_files/." "$OUT/output_files/" 2>/dev/null
  SYS_LE=$(grep 'Total FPGA Logic Elements' "$OUT/comp_fpga.txt" | tr -dc '0-9')
  SYS_FMAX=$(grep 'Max FPGA Frequency' "$OUT/comp_fpga.txt" | awk '{print $4}')
  SYS_MEMBITS=$(grep 'Total FPGA memory bits' "$OUT/comp_fpga.txt" | tr -dc '0-9')
  ls -l "$MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_${XLR}.sof" || die ".sof not produced"
fi

#--------------------------------------------------------------- 7. handoff
echo; echo "===== 7. handoff block (docs/HANDOFF.md) ====="
{
echo "## HANDOFF $TAG $(date +%Y-%m-%d)"
echo
echo "bitstream   : \$MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_${XLR}.sof"
echo "              (desktop shortcut: k5_xbox_links/fpga_prog_files/)"
echo "enums md5   : $ENUMS_MD5"
echo "commit      : $(cd "$REPO" && git rev-parse HEAD 2>/dev/null)   [working tree: $(cd "$REPO" && git status --porcelain | wc -l) modified files]"
echo
echo "download    : the .sof, plus sw/apps/$XLR/ and sw/apps/sud_shared/"
echo "              -- from the SAME build, in the SAME sitting"
echo
echo -n "expected    : "
for B in $BOARDS; do printf "%s %s / " "$B" "$(cyc 'Sudoku solve' "$OUT/sim_$B.txt")"; done; echo "solve cycles in simulation"
echo -n "              (setup+load: "
for B in $BOARDS; do printf "%s %s / " "$B" "$(cyc 'Board setup\+load' "$OUT/sim_$B.txt")"; done; echo ")"
echo "              hardware must match these EXACTLY - they are cycle counts, not timings"
echo
echo "cost        : LEs $LE (fitter $LE_FIT)  registers $REGS  F_max standalone $FMAX MHz"
echo "              system F_max $SYS_FMAX MHz  memory bits $SYS_MEMBITS"
} | tee "$OUT/HANDOFF.txt"

echo
echo "Logs: $OUT"
echo "NOT COMMITTED - review and commit yourself."
