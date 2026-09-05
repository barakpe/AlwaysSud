#!/bin/bash
# runtb3.sh <solverfile> <mode> <variantdef|-> <puzzles> <out>
# Args captured and absolutised BEFORE sourcing (SKILL.md trap #2).
S=$1; M=$2; V=$3; P=$(readlink -m "$4"); O=$(readlink -m "$5")
B=/project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud
source "$B/.claude/skills/cloud-measure/k5_env.sh"
EX=""; [ "$V" != "-" ] && EX="+define+$V"
D=$(mktemp -d "$B/explore/sim/xr.XXXXXX"); cd "$D" || exit 2
xrun -sv -q -64bit -timescale 1ns/1ps +define+SUD_MODE=$M $EX \
  +incdir+$B/explore/rtl $B/explore/rtl/sud_geom_pkg.sv $B/explore/rtl/$S \
  $B/explore/rtl/tb_solver.sv +PUZZLES="$P" +OUT="$O" 2>&1 \
  | grep -E "tb_solver:|\*E,|\*F," | head -6
cd "$B/explore/sim" && rm -rf "$D"
