#!/bin/bash
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
explore/model/arch v0 --list explore/puzzles/ho_published.txt --each --quiet 2>/dev/null \
  | grep -E '^[0-9]+' > explore/sim/v0_published_each.txt
awk -v h=128760553 '{c[NR]=$2} END{n=asort(c); b=0; for(i=1;i<=n;i++) if(c[i]<h) b++;
  printf "v0 on ho_published: n=%d, hard1=%d is at percentile %.1f (max=%d, %.1fx hard1)\n",
  n, h, 100.0*b/n, c[n], c[n]/h}' explore/sim/v0_published_each.txt > explore/sim/hard1_percentile.txt 2>/dev/null \
  || python3 -c "
vals=sorted(int(l.split()[1]) for l in open('explore/sim/v0_published_each.txt'))
h=128760553; b=sum(1 for v in vals if v<h)
print('v0 on ho_published: n=%d, hard1=%d sits at percentile %.1f (max=%d = %.1fx hard1)'%(len(vals),h,100.0*b/len(vals),vals[-1],vals[-1]/h))
" > explore/sim/hard1_percentile.txt
cat explore/sim/hard1_percentile.txt
