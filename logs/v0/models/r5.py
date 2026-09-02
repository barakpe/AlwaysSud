#!/usr/bin/env python3
"""
How much does adding more inference INSIDE one round buy?

Key property preserved at every level: everything is recomputed from the 27 'used'
registers each round. Nothing is carried between rounds. That is what keeps undo
cheap (see Task 2d) - it costs combinational depth, not state.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rounds import load, State, UNITS, ROW, COL, BOX, FULL

LEVELS = ["naked", "naked+hidden", "+naked-pairs", "+pointing"]

def candidates(st, level):
    """81 masks, recomputed from used regs, then refined by stateless inference."""
    m = [0]*81
    for i in range(81):
        if st.val[i] == 0:
            m[i] = FULL & ~(st.ru[ROW[i]] | st.cu[COL[i]] | st.bu[BOX[i]])
    if level >= 2:
        # naked pairs: two empty cells in a unit with the SAME 2-candidate mask
        # => those 2 digits cannot appear elsewhere in that unit.
        for u in UNITS:
            e = [i for i in u if st.val[i] == 0]
            for a in range(len(e)):
                ma = m[e[a]]
                if bin(ma).count("1") != 2: continue
                for b in range(a+1, len(e)):
                    if m[e[b]] == ma:
                        for k in e:
                            if k != e[a] and k != e[b]:
                                m[k] &= ~ma
    if level >= 3:
        # pointing pairs / box-line: if within a box all spots for digit d lie in one
        # row (or column), d cannot appear elsewhere in that row (column), and vice versa.
        for b in range(9):
            box = [i for i in range(81) if BOX[i] == b]
            for d in range(9):
                bit = 1 << d
                spots = [i for i in box if st.val[i] == 0 and (m[i] & bit)]
                if not spots: continue
                rs = set(ROW[i] for i in spots); cs = set(COL[i] for i in spots)
                if len(rs) == 1:
                    r = rs.pop()
                    for i in range(81):
                        if ROW[i] == r and BOX[i] != b and st.val[i] == 0: m[i] &= ~bit
                if len(cs) == 1:
                    c = cs.pop()
                    for i in range(81):
                        if COL[i] == c and BOX[i] != b and st.val[i] == 0: m[i] &= ~bit
        for u in UNITS[:18]:                      # rows and cols
            for d in range(9):
                bit = 1 << d
                spots = [i for i in u if st.val[i] == 0 and (m[i] & bit)]
                if spots and len(set(BOX[i] for i in spots)) == 1:
                    bx = BOX[spots[0]]
                    for i in range(81):
                        if BOX[i] == bx and i not in u and st.val[i] == 0: m[i] &= ~bit
    return m

def one_round(st, level):
    if st.nsolved == 81: return "solved", []
    m = candidates(st, level)
    for i in range(81):
        if st.val[i] == 0 and m[i] == 0: return "contradiction", []
    forced = {}
    for i in range(81):
        if st.val[i] == 0 and m[i] and (m[i] & (m[i]-1)) == 0:
            forced[i] = m[i].bit_length()
    if level >= 1:
        for u in UNITS:
            for d in range(1, 10):
                bit = 1 << (d-1)
                spots = [i for i in u if st.val[i] == 0 and (m[i] & bit)]
                if len(spots) == 1:
                    i = spots[0]
                    if i in forced and forced[i] != d: return "contradiction", []
                    forced[i] = d
                elif not spots and not any(st.val[i] == d for i in u):
                    return "contradiction", []
    if not forced: return "stuck", []
    for i, d in sorted(forced.items()):
        if not st.place(i, d): return "contradiction", []
    return "placed", sorted(forced.items())

def solve(cells, level):
    st0 = State(cells=cells)
    c = dict(rounds=0, branch=0, trials=0, maxpl=0)
    def search(st):
        while True:
            c["rounds"] += 1
            status, placed = one_round(st, level)
            if placed: c["maxpl"] = max(c["maxpl"], len(placed))
            if status != "placed": break
        if status == "solved": return st
        if status == "contradiction": return None
        c["branch"] += 1
        m = candidates(st, level)
        i = min((bin(m[j]).count("1"), j) for j in range(81) if st.val[j] == 0)[1]
        for d in range(1, 10):
            if m[i] >> (d-1) & 1:
                c["trials"] += 1
                nxt = State(other=st)
                if nxt.place(i, d):
                    got = search(nxt)
                    if got: return got
        return None
    sys.setrecursionlimit(50000)
    out = search(st0)
    assert out is not None and out.nsolved == 81
    for u in UNITS: assert sorted(out.val[i] for i in u) == list(range(1,10))
    return c

print("Rounds / branch-points, by how much inference one round does")
print("(guesses = branch points, the convention that reproduces Barak's table)\n")
hdr = "%-10s" % "board"
for L in LEVELS: hdr += " | %-18s" % L
print(hdr); print("%-10s" % "" + (" | %6s %5s %5s" % ("rounds","gss","maxpl"))*len(LEVELS))
print("-"*90)
for n in ["easy1","20blanks","51blanks","hard1"]:
    cells = load(n); line = "%-10s" % n
    for L in range(len(LEVELS)):
        c = solve(cells, L)
        line += " | %6d %5d %5d" % (c["rounds"], c["branch"], c["maxpl"])
    print(line)
