#!/bin/bash
# Wait for comp_fpga to release the staged directory, then run the two remaining
# synthesis points ONE AT A TIME. Never overlap: every measure.sh stages into the
# same $MY_K5_PROJ/hw/xlrs/alwaysud (EXPLORATION.md section 8).
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
until grep -q "^FPGA_RESULT" logs/explore-s2fast-fpga.log 2>/dev/null; do sleep 60; done
echo "=== comp_fpga done ==="; grep -A5 "^FPGA_RESULT" logs/explore-s2fast-fpga.log
for e in s2fasttree courseref; do
  echo "=== $e ==="
  ./explore/measure.sh "$e" > "logs/explore-$e.log" 2>&1
  grep -E '^RESULT|STOP' "logs/explore-$e.log"
done
echo QUEUE_DONE
