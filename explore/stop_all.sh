#!/bin/bash
# Stop every synthesis driver and Quartus process. Written to a file so the
# pattern does not appear in the caller's own command line, which is how an
# earlier pkill killed its own shell.
kill 89156 100678 2>/dev/null                 # run_all_syn.sh, deadline.sh
pkill -u "$USER" -f 'explore/measure.sh'
sleep 3
pkill -u "$USER" -x quartus_map
pkill -u "$USER" -x quartus_fit
pkill -u "$USER" -x quartus_sta
sleep 4
pkill -9 -u "$USER" -x quartus_map 2>/dev/null
pkill -9 -u "$USER" -x quartus_fit 2>/dev/null
echo "--- survivors ---"
ps -o pid=,args= -u "$USER" | grep -E 'quartus_|measure\.sh|run_all|deadline' | grep -v grep
echo "(none above means clean)"
