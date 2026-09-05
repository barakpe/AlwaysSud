#!/bin/bash
pkill -u "$USER" -f 'model/gen'
sleep 2
ps -o pid=,args= -u "$USER" | grep 'model/ge''n' | grep -v grep
echo "(nothing above = stopped)"
