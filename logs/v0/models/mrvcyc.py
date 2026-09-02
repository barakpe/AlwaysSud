#!/usr/bin/env python3
"""
Cycle-accurate model of claude_mrv's FSM, to check the assignment's '~1,000 cycles'.

Mirrors sud_solver_mrv_claude.sv exactly:
  S_INIT      : 81 cycles, one cell per cycle
  S_ADVANCE   : 1 cycle. Picks the unassigned cell with fewest candidates
                (first such cell in raster order on ties), tries its SMALLEST legal
                digit, pushes, stays in S_ADVANCE. If that cell has no legal digit
                -> S_BACKTRACK (still 1 cycle).
  S_BACKTRACK : 1 cycle. If the top entry has a next legal digit, re-place it and
                go to S_ADVANCE. Otherwise clear it, pop, stay in S_BACKTRACK.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rounds import load, ROW, COL, BOX, UNITS, FULL

def run(cells, cap=400_000_000):
    val = list(cells)
    ru=[0]*9; cu=[0]*9; bu=[0]*9
    for i,v in enumerate(cells):
        if v:
            b=1<<(v-1); ru[ROW[i]]|=b; cu[COL[i]]|=b; bu[BOX[i]]|=b
    fixed=[v!=0 for v in cells]
    stack=[]                      # (cell, digit)
    cyc=81                        # S_INIT
    state='ADV'
    adv=0; bt=0
    while cyc < cap:
        if state=='ADV':
            cyc+=1; adv+=1
            best=None
            for i in range(81):
                if not fixed[i] and val[i]==0:
                    m=FULL & ~(ru[ROW[i]]|cu[COL[i]]|bu[BOX[i]])
                    n=bin(m).count("1")
                    if best is None or n<best[0]:
                        best=(n,i,m)
            if best is None:
                return dict(cycles=cyc, adv=adv, bt=bt, ok=True, val=val)
            n,i,m=best
            d=None
            for k in range(9):
                if m>>k & 1: d=k+1; break
            if d is None:
                state='BT'; continue
            val[i]=d; b=1<<(d-1)
            ru[ROW[i]]|=b; cu[COL[i]]|=b; bu[BOX[i]]|=b
            stack.append((i,d))
        else:
            cyc+=1; bt+=1
            if not stack:
                return dict(cycles=cyc, adv=adv, bt=bt, ok=False, val=val)
            i,d=stack[-1]
            b=1<<(d-1)
            ru[ROW[i]]&=~b; cu[COL[i]]&=~b; bu[BOX[i]]&=~b
            m=FULL & ~(ru[ROW[i]]|cu[COL[i]]|bu[BOX[i]])
            nd=None
            for k in range(d,9):
                if m>>k & 1: nd=k+1; break
            if nd is not None:
                val[i]=nd; nb=1<<(nd-1)
                ru[ROW[i]]|=nb; cu[COL[i]]|=nb; bu[BOX[i]]|=nb
                stack[-1]=(i,nd); state='ADV'
            else:
                val[i]=0; stack.pop()
    return dict(cycles=cyc, adv=adv, bt=bt, ok=None, val=val)

GOLD=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bench", "golden")
print("claude_mrv FSM cycle model (S_INIT 81 + one cycle per ADVANCE/BACKTRACK step)\n")
print("%-10s %12s %10s %10s   %s" % ("board","CYCLES","advances","backtracks","grid"))
for n in ["easy1","20blanks","51blanks","hard1"]:
    r=run(load(n))
    want=open(os.path.join(GOLD,n+".grid")).read().strip()
    got="".join(str(v) for v in r["val"])
    tag = "MATCH" if (r["ok"] and got==want) else ("cap hit" if r["ok"] is None else "FAIL")
    print("%-10s %12s %10d %10d   %s" % (n, "{:,}".format(r["cycles"]), r["adv"], r["bt"], tag))
print("\nAssignment claims: 'on the order of 1,000 cycles to solve the hard1 board'")
