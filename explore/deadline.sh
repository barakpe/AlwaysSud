#!/bin/bash
# Give the s2fast fit a bounded extra window, then move on regardless.
#
# WHY A DEADLINE: s2fast's F_max refines a number I already have (s2, the same
# algorithm in a different coding style, measured at 22.34 MHz). mrvonly and
# s2fastdiag are new axes - they are the difference between "MRV is the wrong
# first rung" being an argument and being a measurement. On a 2-core box only
# one fit runs at a time, so waiting has a real price.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
END=$(( $(date +%s) + 2700 ))          # 45 minutes
while [ "$(date +%s)" -lt "$END" ]; do
  grep -qE '^RESULT s2fast:|STOP' logs/explore-s2fast.log 2>/dev/null && break
  sleep 60
done
if grep -qE '^RESULT s2fast:' logs/explore-s2fast.log 2>/dev/null; then
  echo "s2fast finished inside the window:"; grep -E '^RESULT' logs/explore-s2fast.log
else
  echo "s2fast did not finish within the deadline - stopping it and moving on."
  pkill -u "$USER" -f 'measure''.sh s2fast'
  sleep 3
  pkill -u "$USER" -x quartus_fit; sleep 5; pkill -9 -u "$USER" -x quartus_fit
  echo "PARTIAL: s2fast map-stage numbers only (LEs from Analysis & Synthesis)."
fi
sleep 10
echo "=== mrvonly (prices 'add MRV to the reference solver' on its own) ==="
./explore/measure.sh mrvonly > logs/explore-mrvonly.log 2>&1
grep -E '^RESULT|STOP' logs/explore-mrvonly.log
echo "=== s2fastdiag (prices X-Sudoku) ==="
./explore/measure.sh s2fastdiag > logs/explore-s2fastdiag.log 2>&1
grep -E '^RESULT|STOP' logs/explore-s2fastdiag.log
echo DEADLINE_DONE
