#!/bin/bash
# Publish a release for every bitstream as it appears. Resumable and idempotent:
# a design whose release already exists is skipped.
#
# Each release records WHICH experiment directory built it, because hw/xlrs can
# only be one design at a time. The laptop runs explore/use_design.sh <name>
# first so the tree matches the .sof it is about to program.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
expected() {  # small-board solve-window cycles, measured in K5 simulation
  case "$1" in
    s2fast|s2fasttree) echo "easy1 187 / 20blanks 211 / 51blanks 235|295 solver + ~183 = ~478";;
    s2rr)              echo "easy1 187 / 20blanks 211 / 51blanks 235|940 solver + ~183 = ~1123";;
    s2fastmrv)         echo "easy1 187 / 20blanks 211 / 51blanks 235|193 solver + ~183 = ~376";;
    *)                 echo "unknown|unknown";;
  esac
}
for e in s2fastmrv s2rr s2fasttree; do
  TAG="explore-$e"
  gh release view "$TAG" --repo barakpe/AlwaysSud >/dev/null 2>&1 && { echo "== $TAG exists, skip"; continue; }
  SOF="logs/explore-$e/fpga/k5_xbox_alwaysud.sof"
  [ -f "$SOF" ] || { echo "== $e: no bitstream yet"; continue; }
  EXP=$(expected "$e"); SMALL="${EXP%%|*}"; HARD="${EXP##*|}"
  N="logs/explore-$e/fpga/HANDOFF.txt"
  { echo "commit: $(git rev-parse HEAD)"
    echo "branch: explore/opus5-phases"
    echo "built_from: explore/exp/$e/"
    echo "enums_md5: $(md5sum sw/apps/alwaysud/alwaysud_enums.svh | cut -d' ' -f1)"
    echo "sof_md5: $(md5sum "$SOF" | cut -d' ' -f1)"
    echo
    echo "BEFORE VALIDATING, make the tree match the bitstream:"
    echo "    ./explore/use_design.sh $e"
    echo "hw/xlrs/alwaysud is only ever ONE design at a time, and board-validate"
    echo "checks the tree against this commit, not against the .sof - so without"
    echo "that step the check can pass while you program something else."
    echo
    echo "expected solve cycles (hardware must match EXACTLY):"
    echo "  $SMALL"
    echo "setup+load cycles: 235"
    echo "hard1 PREDICTION: $HARD cycles"
    echo
    grep -E "system LEs|system F_max|memory bits" "logs/explore-$e-fpga.log" 2>/dev/null | sed 's/^ */system:  /'
    grep -m1 "^RESULT $e:" "logs/explore-$e.log" 2>/dev/null | sed 's/^/standalone: /'
    echo
    echo "baseline: v0 is 128,760,739 cycles at 87.02 MHz = 1.4797 s."
  } > "$N"
  echo "== publishing $TAG"
  .claude/skills/cloud-measure/publish_release.sh "$TAG" "$N" "$SOF" sw/apps/alwaysud/alwaysud_enums.svh
done
