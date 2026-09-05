#!/bin/bash
# Publish the exploration release once comp_fpga has produced a bitstream.
#
#   ./explore/release_when_ready.sh          # waits for the build, then publishes
#
# NOT run automatically. Publishing a GitHub release is an outward-facing write
# that creates a tag ref on the remote, so it stays a human decision - the same
# reason cloud-measure/SKILL.md calls it out as "the one write to GitHub".
#
# It uses the repo's own publish_release.sh so the .sof and the enums contract go
# into ONE release object. That binding is the point: a stale .svh against a fresh
# bitstream compiles clean and misbehaves at runtime, and attaching them to the
# same release makes fetching them apart impossible rather than merely discouraged.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
TAG=explore-s2fast
OUT=logs/explore-s2fast/fpga
LOG=logs/explore-s2fast-fpga.log

echo "waiting for comp_fpga to finish (it may still be running)..."
until grep -q "^FPGA_RESULT" "$LOG" 2>/dev/null; do sleep 60; done

if ! grep -q "BITSTREAM OK" "$LOG"; then
  echo
  echo "NO RELEASE - comp_fpga did not produce a bitstream."
  echo "That is not a script failure; it IS the answer to 'we are over the 20,000-LE"
  echo "limit, can we even run it?'. See $LOG, and fall back to the"
  echo "naked-singles-only design (still ~2,877x fewer cycles than v0's worst case)."
  exit 1
fi

SOF="$OUT/k5_xbox_alwaysud.sof"
SVH=sw/apps/alwaysud/alwaysud_enums.svh
[ -f "$SOF" ] || { echo "NO RELEASE: .sof missing at $SOF"; exit 1; }

{
echo "commit: $(git rev-parse HEAD)"
echo "branch: explore/opus5-phases"
echo "enums_md5: $(md5sum $SVH | cut -d' ' -f1)"
echo "sof_md5: $(md5sum "$SOF" | cut -d' ' -f1)"
echo
echo "DESIGN: s2fast - candidate masks + naked/hidden singles placed as forced,"
echo "non-branching moves, with one-hot selection. Drop-in replacement for"
echo "alwaysud_solver.sv: identical ports, wrapper and driver untouched."
echo
echo "expected solve cycles (hardware must match EXACTLY):"
echo "  easy1 187 / 20blanks 211 / 51blanks 235"
echo "setup+load cycles: 235"
echo
echo "hard1 PREDICTION: 295 solver cycles + ~183 window overhead = ~478 cycles."
echo "That is a prediction, never a measurement - the board is the first place it"
echo "will ever run. The model behind it agreed with RTL simulation EXACTLY on"
echo "3,491 held-out puzzles across two geometries, so if hard1 comes back far from"
echo "478 the interesting question is the wrapper, not the solver."
echo
echo "These are SOLVE-WINDOW numbers with ALWAYSUD_SPLIT_TIMERS=1 - the window"
echo "docs/MEASUREMENT.md defines. Never compare them to unsplit totals."
echo
echo "standalone: LEs 25098 / registers 2907 / 0 memory bits / F_max 24.37 MHz"
grep -E "system LEs|system F_max|memory bits" "$LOG" | sed 's/^ */system:     /'
echo
echo "correctness: easy1 / 20blanks / 51blanks all PASS in K5 simulation, against"
echo "bench/golden AND the app's own final checker."
echo
echo "baseline for comparison: v0 is 128,760,739 cycles at 87.02 MHz = 1.4797 s."
} > "$OUT/HANDOFF.txt"

echo; cat "$OUT/HANDOFF.txt"; echo
.claude/skills/cloud-measure/publish_release.sh "$TAG" "$OUT/HANDOFF.txt" "$SOF" "$SVH"
