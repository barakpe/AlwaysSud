#!/bin/bash
# s2rr (D6) measured 21.89 MHz against a 57 MHz break-even - 2.6x worse on rate.
# Its comp_fpga is 4-6 h of a 1-core box for a bitstream of a design nobody should
# program. Stop it; the machine is worth more free.
pkill -u "$USER" -f 'bitstreams2'
sleep 2
pkill -u "$USER" -x quartus_fit; pkill -u "$USER" -x quartus_map
sleep 3
ps -o pid=,args= -u "$USER" | grep -E 'quartus_|bitstream' | grep -v grep
echo "(nothing above = machine is free)"
