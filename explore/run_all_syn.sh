#!/bin/bash
# All synthesis data points, one after another. They cannot overlap: they share
# the staged $MY_K5_XLRS/alwaysud directory.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
for e in "$@"; do
  echo "############ $e ############"
  ./explore/measure.sh "$e" > "logs/explore-$e.log" 2>&1
  grep -E "^RESULT|^##########" "logs/explore-$e.log" | tail -3
done
echo ALL_SYN_DONE
