#!/bin/bash
# Make hw/xlrs/alwaysud BE a given experiment, so the repo tree matches the
# bitstream you are about to program.
#
#   ./explore/use_design.sh s2rr
#
# WHY THIS EXISTS: board-validate checks the tree against the release's COMMIT,
# not against the bitstream. Both can say v0 while the .sof says something else,
# and the check still passes - see phase 20. Running this first makes the two
# agree for real.
N="${1:?usage: use_design.sh <experiment name, e.g. s2fast | s2rr | s2fasttree>}"
R="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$R/explore/exp/$N" ] || { echo "no such experiment: $N"; ls "$R/explore/exp"; exit 2; }
rm -f "$R/hw/xlrs/alwaysud/"*
cp "$R/explore/exp/$N"/* "$R/hw/xlrs/alwaysud/"
echo "hw/xlrs/alwaysud is now '$N':"
ls "$R/hw/xlrs/alwaysud"
echo
echo "commit this before publishing or validating, so the tree and the bitstream agree."
