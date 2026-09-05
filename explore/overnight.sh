#!/bin/bash
# Overnight queue. RESUMABLE: every step skips itself if its RESULT.txt already
# exists, so a reboot costs you one step, not the night. Just run it again.
#
#   ./explore/overnight.sh                 start / resume
#   grep -h RESULT logs/explore-*/sim/RESULT.txt   see what has landed
#
# WHY qsyn_xlr AND NOT comp_fpga: the assignment defines the score as
#   solve_time_us = cycle_count / max_freq_mhz
# with max_freq "taken from the standalone accelerator synthesis using the
# qsyn_xlr utility, rather than from the full-design comp_fpga result".
# comp_fpga is only needed to make a bitstream to run on the board. So the
# overnight budget goes on qsyn_xlr, which is 30 min - 4 h, not 4 - 8 h.
#
# STRICTLY SEQUENTIAL: every measure.sh stages into the same
# $MY_K5_PROJ/hw/xlrs/alwaysud. Two at once silently destroy each other.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2

# in priority order - if the box reboots, the most valuable ones are already done
QUEUE="s2fasttree s2rr s2fastmrv courseref"

echo "### overnight queue starting $(date)"
echo "### already done: $(ls logs/explore-*/sim/RESULT.txt 2>/dev/null | wc -l) step(s)"

# don't fight comp_fpga for the staging directory
while pgrep -u "$USER" -x quartus_fit >/dev/null || pgrep -u "$USER" -x quartus_map >/dev/null; do
  echo "$(date +%H:%M) waiting - a Quartus run already owns the staged directory"
  sleep 300
done

for e in $QUEUE; do
  if [ -s "logs/explore-$e/sim/RESULT.txt" ]; then
    echo "== $e already done: $(cat logs/explore-$e/sim/RESULT.txt)"; continue
  fi
  echo "== $e starting $(date +%H:%M)"
  ./explore/measure.sh "$e" > "logs/explore-$e.log" 2>&1
  grep -E '^RESULT|^##########' "logs/explore-$e.log" | tail -3
done

echo; echo "### everything measured, $(date)"
printf "%-13s %s\n" DESIGN RESULT
for e in v0base m1 mrvonly s2 s2fast $QUEUE; do
  printf "%-13s %s\n" "$e" "$(cat logs/explore-$e/sim/RESULT.txt 2>/dev/null || echo '-')"
done
echo OVERNIGHT_DONE
