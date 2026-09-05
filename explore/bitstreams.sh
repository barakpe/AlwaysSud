#!/bin/bash
# Second overnight queue: BITSTREAMS, for the designs worth putting on a board.
# Runs only after overnight.sh has finished its qsyn runs, so it never fights for
# the staged directory. RESUMABLE: skips any design whose .sof is already archived.
#
# WHY NOT EVERY DESIGN: comp_fpga measured 4h30 for s2fast on this 1-core box, and
# it is not needed for the SCORE at all - the assignment takes max_freq from
# qsyn_xlr, "rather than from the full-design comp_fpga result". A bitstream is
# only needed to run something on hardware, so only the candidates get one.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2

# s2rr (D6) first: it is the smaller design and the insurance if s2fast's 28.42 MHz
# system timing turns out to matter on the board. s2fasttree second: same size as
# s2fast but possibly faster, so a better bitstream of the same thing.
QUEUE="s2rr s2fasttree"

until grep -q OVERNIGHT_DONE logs/explore-overnight.log 2>/dev/null; do sleep 300; done
echo "### qsyn queue finished, starting bitstreams $(date)"
for e in $QUEUE; do
  if [ -s "logs/explore-$e/fpga/k5_xbox_alwaysud.sof" ]; then
    echo "== $e bitstream already exists, skipping"; continue
  fi
  echo "== $e comp_fpga starting $(date +%H:%M) - expect 4-6 h"
  ./explore/full_fpga.sh "$e" > "logs/explore-$e-fpga.log" 2>&1
  grep -A5 "^FPGA_RESULT" "logs/explore-$e-fpga.log"
done
echo BITSTREAMS_DONE
