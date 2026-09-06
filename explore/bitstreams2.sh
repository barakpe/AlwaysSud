#!/bin/bash
# Bitstreams, re-prioritised after the overnight qsyn results changed the winner.
# The box rebooted at ~18:32 and killed the previous run, so this starts clean.
#
# s2fastmrv FIRST: it is now the fastest measured design, 14.26 us on hard1.
# RISK: 28,396 LE against s2fast's 25,098, and s2fast already needed three
# placement attempts to fit at 71% of the device. This may not fit at all - which
# is itself the result, and why s2fast keeps its release as the safe fallback.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
for e in s2fastmrv s2rr; do
  if [ -s "logs/explore-$e/fpga/k5_xbox_alwaysud.sof" ]; then
    echo "== $e bitstream already exists, skipping"; continue
  fi
  echo "== $e comp_fpga starting $(date +%H:%M) - expect 4-6 h"
  ./explore/full_fpga.sh "$e" > "logs/explore-$e-fpga.log" 2>&1
  grep -A5 "^FPGA_RESULT" "logs/explore-$e-fpga.log"
  ./explore/autorelease.sh 2>&1 | tail -4
done
echo BITSTREAMS2_DONE
