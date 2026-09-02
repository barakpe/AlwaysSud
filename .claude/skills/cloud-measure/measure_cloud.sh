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
OUT="$REPO/logs/$TAG/sim"; mkdir -p "$OUT"  # one directory per phase; laptop writes hw/
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
  python3 "$REPO/bench/solve_ref.py" --check "$B" "$OUT/sim_$B.txt" 2>&1 | tee -a "$OUT/gate.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || FAILED="$FAILED $B"
done
[ -z "$FAILED" ] || die "correctness MISMATCH on:$FAILED - a faster wrong answer is not a result"
GATE_OK=1

#--------------------------------------------------------------- 5. cycles
# Since 2026-08-29 the app prints THREE performance lines, because solve() ends the
# setup window before calling the solver:
#   "Board setup+load"  board LOAD over 3 bursts + both register handshakes
#   "Sudoku solve"      the search alone   <-- this is the metric the release quotes
#   "Total"             setup+solve, i.e. the single number printed before the split
cyc() { grep -oE "$1 +[0-9,]+" "$2" | grep -oE '[0-9,]+$' | tail -1; }
# Take the value AFTER the colon. comp_fpga labels its lines
#   "Total FPGA Logic Elements (out of about 50K available):   20,560"
# so a bare `tr -dc 0-9` swallows the 50 and yields 5020560. That bug is what put
# "LEs 5020560 / memory bits 9618%" in a handoff block once. Do not reintroduce it.
num() { grep -m1 "$1" "$2" | sed 's/.*: *//' | tr -dc '0-9'; }
mhz() { grep -m1 'Max FPGA Frequency' "$1" | awk '{print $4}'; }

echo; echo "===== 5. cycles ====="
printf "%-10s %12s %12s %12s\n" board setup+load solve total | tee "$OUT/cycles.txt"
for B in $BOARDS; do
  printf "%-10s %12s %12s %12s\n" "$B" \
    "$(cyc 'Board setup\+load' "$OUT/sim_$B.txt")" \
    "$(cyc 'Sudoku solve'       "$OUT/sim_$B.txt")" \
    "$(cyc 'Total'              "$OUT/sim_$B.txt")"
done | tee -a "$OUT/cycles.txt"

#--------------------------------------------------------------- 6. bitstream
FPGA_OK=0
SOF="$MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_${XLR}.sof"
SVH="$MY_K5_PROJ/sw/apps/$XLR/${XLR}_enums.svh"
if [ "$WITH_FPGA" = "--with-fpga" ]; then
  echo; echo "===== 6. comp_fpga (TAKES OVER TEN MINUTES) ====="
  ( cd "$MY_K5_PROJ/hw/gen_fpga" && comp_fpga $XLR ) 2>&1 | tee "$OUT/comp_fpga.txt"
  grep -qE '^ERROR |Something went wrong' "$OUT/comp_fpga.txt" && die "comp_fpga failed"
  grep -q 'Max FPGA Frequency' "$OUT/comp_fpga.txt" || die "comp_fpga produced no system F_max"
  [ -f "$SOF" ] || die ".sof not produced at $SOF"
  mkdir -p "$OUT/output_files"
  cp -a "$MY_K5_PROJ/hw/gen_fpga/output_files/." "$OUT/output_files/" 2>/dev/null
  ls -l "$SOF"
  FPGA_OK=1
fi

#--------------------------------------------------------------- 7. handoff notes
# Format is the spec in docs/HANDOFF.md, "Rules for the notes block". The laptop parses
# this, and the release notes are this file verbatim - so every value here is scraped
# from the logs this run produced. Nothing is templated in by hand.
echo; echo "===== 7. handoff notes (docs/HANDOFF.md) ====="
{
echo "commit: $(cd "$REPO" && git rev-parse HEAD)"
echo "enums_md5: $ENUMS_MD5"
if [ "$FPGA_OK" = 1 ]; then echo "sof_md5: $(md5sum "$SOF" | cut -d' ' -f1)"; else echo "sof_md5: NOT BUILT"; fi
echo
echo "expected solve cycles (hardware must match EXACTLY):"
echo -n "  "
first=1; for B in $BOARDS; do [ $first = 1 ] || echo -n " / "; first=0; echo -n "$B $(cyc 'Sudoku solve' "$OUT/sim_$B.txt")"; done; echo
echo "setup+load cycles: $(cyc 'Board setup\+load' "$OUT/sim_${BOARDS%% *}.txt")"
echo
echo "These are SOLVE-WINDOW numbers, from report_task_performance(\"Sudoku solve\") after"
echo "the timer split - not the pre-split totals, and not report_total_performance(),"
echo "which prints setup+solve."
echo
echo "standalone: LEs $LE / registers $REGS / F_max $FMAX MHz"
if [ "$FPGA_OK" = 1 ]; then
  SMB=$(num 'Total FPGA memory bits' "$OUT/comp_fpga.txt")
  echo "system:     LEs $(num 'Total FPGA Logic Elements' "$OUT/comp_fpga.txt") / F_max $(mhz "$OUT/comp_fpga.txt") MHz / memory bits $(python3 -c "print('%.0f' % ($SMB/1677312*100))")%"
else
  echo "system:     NOT BUILT"
fi
echo
echo "correctness: all three boards PASS, golden gate and app checker"
} | tee "$OUT/HANDOFF.txt"

#--------------------------------------------------------------- 8. publish the release
# The handoff IS a GitHub release (docs/HANDOFF.md). Publishing binds the .sof and the
# .svh atomically, which is the whole point: a stale contract file against a fresh
# bitstream compiles clean and misbehaves at runtime.
if [ "$FPGA_OK" = 1 ] && [ "$GATE_OK" = 1 ]; then
  echo; echo "===== 8. publish release $TAG ====="
  "$HERE/publish_release.sh" "$TAG" "$OUT/HANDOFF.txt" "$SOF" "$SVH" || die "publishing failed"
elif [ "$WITH_FPGA" = "--with-fpga" ]; then
  die "internal: reached publish with FPGA_OK=$FPGA_OK GATE_OK=$GATE_OK"
else
  echo; echo "no --with-fpga, so no bitstream and no release. Nothing to hand off."
fi

echo
echo "Logs: $OUT"
echo "NOT COMMITTED - review and commit yourself."
