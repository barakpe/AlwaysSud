#!/bin/bash
# Build the FULL k5_xbox system for one experiment: does a 25k-LE accelerator
# actually fit and produce a bitstream?  Answers "we are over the 20,000-LE limit
# in docs/MEASUREMENT.md - can we even run it?"
#
# comp_fpga is the only thing that can answer it: qsyn_xlr synthesises the
# accelerator ALONE against a dummy wrapper, so it says nothing about whether the
# accelerator plus the RISC-V, the UART and the memory subsystem fit together.
NAME="$1"                                    # capture BEFORE sourcing
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
source "$REPO/.claude/skills/cloud-measure/k5_env.sh"
XLR=alwaysud; EXP="$REPO/explore/exp/$NAME"; OUT="$REPO/logs/explore-$NAME/fpga"
[ -d "$EXP" ] || { echo "no such experiment: $EXP"; exit 2; }
mkdir -p "$OUT"

echo "===== stage $NAME ====="
rm -rf "$MY_K5_PROJ/hw/xlrs/$XLR" "$MY_K5_PROJ/sw/apps/$XLR" "$MY_K5_PROJ/sw/apps/sud_shared"
mkdir -p "$MY_K5_PROJ/hw/xlrs/$XLR"
cp "$EXP"/* "$MY_K5_PROJ/hw/xlrs/$XLR/" || exit 1
cp -r "$REPO/sw/apps/$XLR" "$REPO/sw/apps/sud_shared" "$MY_K5_PROJ/sw/apps/" || exit 1

echo; echo "===== comp_fpga (the full system - expect HOURS at this size) ====="
date
( cd "$MY_K5_PROJ/hw/gen_fpga" && comp_fpga $XLR ) 2>&1 | tee "$OUT/comp_fpga.txt" | tail -40
date
mkdir -p "$OUT/output_files"
cp -a "$MY_K5_PROJ/hw/gen_fpga/output_files/." "$OUT/output_files/" 2>/dev/null

SOF="$MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_${XLR}.sof"
echo; echo "===== verdict ====="
if grep -qE '^ERROR |Something went wrong' "$OUT/comp_fpga.txt"; then
  echo "FPGA_RESULT $NAME: FAILED - comp_fpga reported an error"
elif [ -f "$SOF" ]; then
  num() { grep -m1 "$1" "$OUT/comp_fpga.txt" | sed 's/.*: *//' | tr -dc '0-9'; }
  SMB=$(num 'Total FPGA memory bits')
  echo "FPGA_RESULT $NAME: BITSTREAM OK"
  echo "  system LEs   : $(num 'Total FPGA Logic Elements') / 49760"
  echo "  system F_max : $(grep -m1 'Max FPGA Frequency' "$OUT/comp_fpga.txt" | awk '{print $4}') MHz  (NOT graded)"
  echo "  memory bits  : $SMB  ($(python3 -c "print('%.0f%%' % ($SMB/1677312*100))" 2>/dev/null))"
  echo "  sof md5      : $(md5sum "$SOF" | cut -d' ' -f1)"
  cp "$SOF" "$OUT/" 2>/dev/null
else
  echo "FPGA_RESULT $NAME: FAILED - no .sof produced"
fi
