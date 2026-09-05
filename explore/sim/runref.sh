#!/bin/bash
# Run the COURSE'S reference MRV solver through the same testbench as everything else.
# NOTE: args are captured and made absolute on the FIRST lines, BEFORE sourcing -
# sourcing startProject.bash overwrites "$@" ($1 becomes a shell prompt string) and
# changes the working directory. cloud-measure/SKILL.md trap #2; it bit me here.
P=$(readlink -m "$1"); O=$(readlink -m "$2")
B=/project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud
source "$B/.claude/skills/cloud-measure/k5_env.sh"
D=$(mktemp -d "$B/explore/sim/xr.XXXXXX"); cd "$D" || exit 2
xrun -sv -q -64bit -timescale 1ns/1ps \
  "$B/reference/ex3.1/sudx_standalone_ref/claude_mrv/sud_solver_mrv_claude.sv" \
  "$B/explore/rtl/ref/alwaysud_solver_courseref.sv" "$B/explore/rtl/tb_solver.sv" \
  +PUZZLES="$P" +OUT="$O" 2>&1 | grep -E "tb_solver:|\*E,|\*F," | head -8
cd "$B/explore/sim" && rm -rf "$D"
