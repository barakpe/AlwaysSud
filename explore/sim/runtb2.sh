#!/bin/bash
# runtb2.sh <solverfile> <mode> <variantdef|-> <puzzles> <out>
set -u
BASE=/project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud/explore
S=$1; M=$2; V=$3; P=$(readlink -m "$4"); O=$(readlink -m "$5")
EX=""; [ "$V" != "-" ] && EX="+define+$V"
D=$(mktemp -d "$BASE/sim/xr.XXXXXX"); cd "$D" || exit 2
xrun -sv -q -64bit -timescale 1ns/1ps +define+SUD_MODE=$M $EX \
    +incdir+$BASE/rtl $BASE/rtl/sud_geom_pkg.sv $BASE/rtl/$S $BASE/rtl/tb_solver.sv \
    +PUZZLES="$P" +OUT="$O" 2>&1 | grep -E "tb_solver:|\*E,|\*F,"
cd "$BASE/sim" && rm -rf "$D"
