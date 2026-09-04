#!/bin/bash
# Wait for the s2fast fit, then take over the staging directory in priority order:
#   1. K5 end-to-end simulation of s2fast  (minutes) - the real correctness gate,
#      and the only way to measure the window overhead on the new design
#   2. mrvonly    - prices "add MRV to the reference solver" as its own build
#   3. s2fastdiag - prices X-Sudoku
# s2fastmrv is deliberately last and may not run: the decision rule for MRV can be
# stated from cycles alone, these two cannot.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
until grep -qE '^RESULT s2fast:|STOP' logs/explore-s2fast.log 2>/dev/null; do sleep 30; done
sleep 20
pkill -u "$USER" -f 'run_all_sy''n' 2>/dev/null
sleep 5
echo "=== 1. K5 end-to-end simulation of s2fast ==="
./explore/simonly.sh s2fast > logs/explore-s2fast-sim.log 2>&1
tail -12 logs/explore-s2fast-sim.log
echo "=== 2. mrvonly synthesis ==="
./explore/measure.sh mrvonly > logs/explore-mrvonly.log 2>&1
grep -E '^RESULT|STOP' logs/explore-mrvonly.log
echo "=== 3. s2fastdiag synthesis ==="
./explore/measure.sh s2fastdiag > logs/explore-s2fastdiag.log 2>&1
grep -E '^RESULT|STOP' logs/explore-s2fastdiag.log
echo AFTER_S2FAST_DONE
