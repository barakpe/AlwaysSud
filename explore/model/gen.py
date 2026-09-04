#!/usr/bin/env python3
"""Generate held-out puzzles for a variant, using the repo's own units table.

Minimal puzzles (no given can be removed while keeping a unique solution) are the
hard end of the distribution; --keep stops digging early for the easy end.

  gen.py --variant diagonal -n 200 --out file.txt [--keep 40] [--seed 1]
"""
import sys, os, random, argparse
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bench"))
import units as UNITS

ALL = 0x1FF

def make(variant):
    us = UNITS.units(variant)
    uof = [[] for _ in range(81)]
    for k, u in enumerate(us):
        for c in u:
            uof[c].append(k)
    return us, uof

def solve_count(grid, us, uof, limit=2, rnd=None):
    """Count solutions up to `limit`. grid is a list of 81 ints (0 = empty)."""
    used = [0]*len(us)
    for c, v in enumerate(grid):
        if v:
            b = 1 << (v-1)
            for u in uof[c]:
                if used[u] & b:
                    return 0, None
                used[u] |= b
    g = list(grid)
    out = [0]
    sol = [None]

    def allowed(c):
        m = ALL
        for u in uof[c]:
            m &= ~used[u]
        return m

    def rec():
        best, bestn = -1, 10
        for c in range(81):
            if g[c]:
                continue
            n = bin(allowed(c)).count("1")
            if n < bestn:
                bestn, best = n, c
                if n == 0:
                    return
        if best < 0:
            out[0] += 1
            if sol[0] is None:
                sol[0] = list(g)
            return
        ds = [d for d in range(1, 10) if allowed(best) >> (d-1) & 1]
        if rnd:
            rnd.shuffle(ds)
        for d in ds:
            b = 1 << (d-1)
            g[best] = d
            for u in uof[best]:
                used[u] |= b
            rec()
            g[best] = 0
            for u in uof[best]:
                used[u] &= ~b
            if out[0] >= limit:
                return
    rec()
    return out[0], sol[0]

def full_grid(us, uof, rnd):
    while True:
        n, s = solve_count([0]*81, us, uof, limit=1, rnd=rnd)
        if n:
            return s

def dig(sol, us, uof, rnd, keep=0):
    g = list(sol)
    order = list(range(81))
    rnd.shuffle(order)
    for c in order:
        if keep and sum(1 for x in g if x) <= keep:
            break
        v = g[c]
        g[c] = 0
        n, _ = solve_count(g, us, uof, limit=2)
        if n != 1:
            g[c] = v
    return g

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="classic")
    ap.add_argument("-n", type=int, default=50)
    ap.add_argument("--out", required=True)
    ap.add_argument("--keep", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    us, uof = make(a.variant)
    rnd = random.Random(a.seed)
    with open(a.out, "w") as f:
        for i in range(a.n):
            sol = full_grid(us, uof, rnd)
            p = dig(sol, us, uof, rnd, a.keep)
            f.write("".join("." if x == 0 else str(x) for x in p) + "\n")
            f.flush()
            if (i+1) % 25 == 0:
                print("  %s %d/%d (clues %d)" % (a.variant, i+1, a.n,
                      sum(1 for x in p if x)), file=sys.stderr)
    print("wrote %s" % a.out, file=sys.stderr)
