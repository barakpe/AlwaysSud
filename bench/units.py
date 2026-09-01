#!/usr/bin/env python3
"""
The units table: the single place that knows which cells constrain which.

A Sudoku rule is "these 9 cells hold the digits 1..9 exactly once". A *unit* is one
such group. Classic Sudoku has 27 of them - 9 rows, 9 columns, 9 boxes - and every
other rule in the solver, the checker and the diagnosis is derived from that list
rather than from hardcoded row/column/box arithmetic.

**Why this exists.** The hackathon variant is revealed hours to two days before, and
the whole point is that a variant is then a change to *this file* and nothing else.
Before this table existed, `bench/solve_ref.py` hardcoded standard geometry in three
separate places and `bench/diagnose.py` had a fourth copy - so the correctness gate
would have cheerfully passed a solver that ignored a new constraint. A gate that
cannot fail is not a gate.

The same shape is what the RTL wants: a unit is a set of cells whose `used` masks OR
together, so adding a unit is adding a term to an OR, not a rewrite.

## What is and is not expressible here

Expressible - anything of the form "these N cells are all different":

    classic     9 rows + 9 columns + 9 boxes                        27 units
    diagonal    classic + the two main diagonals (X-Sudoku)         29 units
    windoku     classic + four offset 3x3 "hyper" boxes             31 units
    jigsaw      rows + columns + nine irregular shapes              27 units

NOT expressible: rules that are not all-different over a fixed cell set - anti-knight,
thermo, killer cages with sums, inequality constraints. If the variant is one of those,
this file is the wrong tool and the gate must be extended, not reconfigured. Say so
out loud rather than pretending the table covers it.
"""

N    = 9
NCELL = N * N


def _rows():
    return [[r * N + c for c in range(N)] for r in range(N)]


def _cols():
    return [[r * N + c for r in range(N)] for c in range(N)]


def _boxes():
    out = []
    for b in range(N):
        br, bc = (b // 3) * 3, (b % 3) * 3
        out.append([(br + k // 3) * N + bc + k % 3 for k in range(N)])
    return out


def _diagonals():
    return [[i * N + i for i in range(N)],
            [i * N + (N - 1 - i) for i in range(N)]]


def _hyper():
    # The four Windoku "extra" boxes, at rows/cols 1-3 and 5-7.
    out = []
    for br in (1, 5):
        for bc in (1, 5):
            out.append([(br + k // 3) * N + bc + k % 3 for k in range(N)])
    return out


VARIANTS = {
    "classic":  lambda: _rows() + _cols() + _boxes(),
    "diagonal": lambda: _rows() + _cols() + _boxes() + _diagonals(),
    "windoku":  lambda: _rows() + _cols() + _boxes() + _hyper(),
}


def units(variant="classic"):
    """The list of units for a variant. Each unit is a list of cell indices."""
    if variant not in VARIANTS:
        raise SystemExit("unknown variant %r - known: %s\n"
                         "Add it to VARIANTS in bench/units.py; that is the whole change."
                         % (variant, ", ".join(sorted(VARIANTS))))
    u = VARIANTS[variant]()
    validate(u, variant)
    return u


def validate(us, variant):
    """A malformed table would silently weaken the gate, so check it every time."""
    for k, u in enumerate(us):
        if len(u) != N:
            raise SystemExit("variant %s: unit %d has %d cells, expected %d"
                             % (variant, k, len(u), N))
        if len(set(u)) != N:
            raise SystemExit("variant %s: unit %d repeats a cell" % (variant, k))
        for i in u:
            if not 0 <= i < NCELL:
                raise SystemExit("variant %s: unit %d has out-of-range cell %d"
                                 % (variant, k, i))
    covered = set(i for u in us for i in u)
    if len(covered) != NCELL:
        missing = sorted(set(range(NCELL)) - covered)
        raise SystemExit("variant %s: %d cell(s) belong to no unit, e.g. %s - they would "
                         "be unconstrained and the gate would pass anything there"
                         % (variant, len(missing), missing[:8]))


def peers(us):
    """peers[i] = every cell sharing a unit with i, excluding i."""
    p = [set() for _ in range(NCELL)]
    for u in us:
        for i in u:
            p[i].update(u)
    for i in range(NCELL):
        p[i].discard(i)
    return [sorted(s) for s in p]


def units_of(us):
    """units_of[i] = the units containing cell i."""
    m = [[] for _ in range(NCELL)]
    for u in us:
        for i in u:
            m[i].append(u)
    return m


def illegal_units(grid, us, labels=None):
    """Names of units containing a repeated non-zero digit. grid is 81 ints or chars."""
    bad = []
    for k, u in enumerate(us):
        seen = [str(grid[i]) for i in u if str(grid[i]) != "0"]
        if len(seen) != len(set(seen)):
            bad.append(labels[k] if labels else "unit %d" % k)
    return bad


def labels(variant="classic"):
    """Human names, in the same order as units(variant)."""
    out = (["row %d" % r for r in range(N)]
           + ["col %d" % c for c in range(N)]
           + ["box %d" % b for b in range(N)])
    if variant == "diagonal":
        out += ["diagonal \\", "diagonal /"]
    elif variant == "windoku":
        out += ["hyper %d" % i for i in range(4)]
    return out


if __name__ == "__main__":
    for v in sorted(VARIANTS):
        us = units(v)
        p = peers(us)
        print("%-9s %2d units, peers/cell min=%d max=%d"
              % (v, len(us), min(len(x) for x in p), max(len(x) for x in p)))
