#!/usr/bin/env python3
"""rate = (solver cycles + wrapper overhead) / F_max.

The wrapper overhead is the gap between the solver FSM's own cycle count and what
report_task_performance("Sudoku solve") prints: the SOLVE/STORE states, the three
memory write bursts, and the RISC-V software poll loop noticing `done`. Measured on
v0 as 180/189/200/186 for easy1/20blanks/51blanks/hard1 (model vs hardware), so
186 is used for hard1 and 200 as the pessimistic figure for a bound.
"""
import sys
OV = 186
def rate(cyc, fmax_mhz, ov=OV):
    return (cyc + ov) / (fmax_mhz * 1e6)
def fmt(s):
    return ("%.4f s" % s) if s >= 1 else ("%.3f ms" % (s*1e3)) if s >= 1e-3 else ("%.2f us" % (s*1e6))
if __name__ == "__main__":
    rows = [a.split(":") for a in sys.argv[1:]]
    base = None
    print("%-14s %14s %9s %14s %10s" % ("design", "cycles", "F_max", "rate", "vs v0"))
    for name, cyc, f in rows:
        r = rate(int(cyc), float(f))
        if base is None: base = r
        print("%-14s %14s %9s %14s %9.1fx" % (name, "{:,}".format(int(cyc)), f, fmt(r), base/r))
