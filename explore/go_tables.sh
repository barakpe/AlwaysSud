#!/bin/bash
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
ARCHS="m1 s0 s1 s2 s2u m2 s2m s2um p1 p2 p3 p4" ./explore/table.sh > explore/TABLES2.txt 2>&1
echo TABLES_DONE >> explore/TABLES2.txt
