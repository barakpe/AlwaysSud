#!/usr/bin/env python3
"""
Independent model of the parallel-propagation solver Barak proposes.

Deliberately written from scratch; shares no code with bench/solve_ref.py.
Representation is chosen to mirror the HARDWARE, not to be convenient:

  * state is exactly what the RTL would hold: 81 solved values (0 = empty) plus
    the three 9-bit "used" registers per row / column / box.
  * a ROUND is one clock-domain step: recompute all 81 candidate masks straight
    from the used registers, decide which cells are forced, place ALL of them at
    once, then update the used registers.
  * nothing is remembered between rounds. No candidate-elimination chains, no
    pencil marks carried forward. That is what the proposed hardware can do.

Round accounting: a round is counted for every iteration the machine executes,
INCLUDING the final one that finds nothing left to place (the machine has to run
it to learn that it is done). So rounds = productive_rounds + 1 on a board that
propagates to completion.

Guesses are counted every time the machine has to branch, including branches that
turn out to be wrong. Rounds inside failed branches are counted too - the hardware
pays for them.
"""
import sys, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO   = os.path.abspath(os.path.join(HERE, "..", ".."))   # logs/<tag>/ -> repo root
BOARDS = os.path.join(REPO, "sw", "apps", "sud_shared")
FULL = 0x1FF

ROW = [i // 9 for i in range(81)]
COL = [i % 9 for i in range(81)]
BOX = [(i // 9 // 3) * 3 + (i % 9) // 3 for i in range(81)]
UNITS = ([[r * 9 + c for c in range(9)] for r in range(9)] +
         [[r * 9 + c for r in range(9)] for c in range(9)] +
         [[(b // 3 * 3 + dr) * 9 + (b % 3 * 3 + dc) for dr in range(3) for dc in range(3)]
          for b in range(9)])


def load(name):
    txt = open(os.path.join(BOARDS, "sudoku_input_%s.txt" % name)).read()
    v = [int(t, 16) for t in re.findall(r"[0-9A-Fa-f]{2}", txt)]
    assert len(v) == 81, "%s: got %d cells" % (name, len(v))
    return v


class State:
    """Solved values + the three used registers. This is the whole hardware state."""
    __slots__ = ("val", "ru", "cu", "bu", "nsolved")

    def __init__(self, cells=None, other=None):
        if other is not None:
            self.val = other.val[:]; self.ru = other.ru[:]
            self.cu = other.cu[:];  self.bu = other.bu[:]
            self.nsolved = other.nsolved
            return
        self.val = [0] * 81
        self.ru = [0] * 9; self.cu = [0] * 9; self.bu = [0] * 9
        self.nsolved = 0
        for i, v in enumerate(cells):
            if v and not self.place(i, v):
                raise ValueError("given board is already illegal at cell %d" % i)

    def place(self, i, v):
        b = 1 << (v - 1)
        if (self.ru[ROW[i]] | self.cu[COL[i]] | self.bu[BOX[i]]) & b:
            return False                      # conflicts with an existing value
        self.val[i] = v
        self.ru[ROW[i]] |= b; self.cu[COL[i]] |= b; self.bu[BOX[i]] |= b
        self.nsolved += 1
        return True

    def masks(self):
        """All 81 candidate masks, recomputed from the used registers. One 'cycle'."""
        m = [0] * 81
        for i in range(81):
            if self.val[i] == 0:
                m[i] = FULL & ~(self.ru[ROW[i]] | self.cu[COL[i]] | self.bu[BOX[i]])
        return m


def one_round(st, use_hidden):
    """
    Execute one round. Returns (status, placed_list).
      status: 'placed' | 'stuck' | 'contradiction' | 'solved'
    Everything here is what the fabric would compute in parallel in one step.
    """
    if st.nsolved == 81:
        return "solved", []
    m = st.masks()

    # dead cell: an empty cell with no candidate at all
    for i in range(81):
        if st.val[i] == 0 and m[i] == 0:
            return "contradiction", []

    forced = {}                                  # cell -> digit

    # naked singles: mask has exactly one bit
    for i in range(81):
        if st.val[i] == 0 and m[i] and (m[i] & (m[i] - 1)) == 0:
            forced[i] = m[i].bit_length()

    if use_hidden:
        # hidden singles: within a unit, a digit that fits in exactly one empty cell
        for u in UNITS:
            for d in range(1, 10):
                b = 1 << (d - 1)
                spots = [i for i in u if st.val[i] == 0 and (m[i] & b)]
                if len(spots) == 1:
                    i = spots[0]
                    if i in forced and forced[i] != d:
                        # same cell forced to two different digits in one round
                        return "contradiction", []
                    forced[i] = d
                elif not spots and not any(st.val[i] == d for i in u):
                    # digit d has nowhere to go in this unit and is not already placed
                    return "contradiction", []

    if not forced:
        return "stuck", []

    # place them ALL at once. Two cells in the same unit forced to the same digit is
    # a contradiction that must be caught in the very cycle they are placed.
    for i, d in sorted(forced.items()):
        if not st.place(i, d):
            return "contradiction", []
    return "placed", sorted(forced.items())


def solve(cells, use_hidden, guess_order="mrv"):
    """Returns dict of counts, or None if the board has no solution."""
    stats = {"rounds": 0, "guesses": 0, "max_placed": 0, "round_sizes": [],
             "rounds_before_first_guess": 0, "placed_by_guess": 0}
    try:
        root = State(cells=cells)
    except ValueError as e:
        return None, str(e)

    seen_guess = [False]

    def propagate(st):
        """Run rounds until solved / stuck / contradiction."""
        while True:
            stats["rounds"] += 1
            if not seen_guess[0]:
                stats["rounds_before_first_guess"] += 1
            status, placed = one_round(st, use_hidden)
            if placed:
                stats["round_sizes"].append(len(placed))
                stats["max_placed"] = max(stats["max_placed"], len(placed))
            if status != "placed":
                return status

    def search(st):
        status = propagate(st)
        if status == "solved":
            return st
        if status == "contradiction":
            return None
        # stuck: branch
        m = st.masks()
        cand = [(bin(m[i]).count("1"), i) for i in range(81) if st.val[i] == 0]
        if guess_order == "mrv":
            _, i = min(cand)
        else:
            _, i = min(cand, key=lambda t: t[1])
        for d in range(1, 10):
            if m[i] >> (d - 1) & 1:
                stats["guesses"] += 1
                seen_guess[0] = True
                stats["placed_by_guess"] += 1
                nxt = State(other=st)
                if nxt.place(i, d):
                    got = search(nxt)
                    if got:
                        return got
        return None

    sys.setrecursionlimit(20000)
    out = search(root)
    return (stats, out)


if __name__ == "__main__":
    names = ["easy1", "20blanks", "51blanks", "hard1"]
    print("%-10s %6s | %-22s | %-22s" % ("board", "blanks", "naked-only", "naked+hidden"))
    print("%-10s %6s | %-10s %-11s | %-10s %-11s" % ("", "", "rounds", "guesses", "rounds", "guesses"))
    print("-" * 72)
    results = {}
    for n in names:
        cells = load(n)
        blanks = sum(1 for v in cells if v == 0)
        row = [n, blanks]
        for hidden in (False, True):
            stats, out = solve(cells, hidden)
            assert out is not None, "%s: NO SOLUTION under model" % n
            results[(n, hidden)] = (stats, out)
            row += [stats["rounds"], stats["guesses"]]
        print("%-10s %6d | %-10d %-11d | %-10d %-11d" % tuple(row))
    print()
    # sanity: every model solution must be a legal, complete grid
    for (n, h), (stats, out) in results.items():
        assert out.nsolved == 81
        for u in UNITS:
            assert sorted(out.val[i] for i in u) == list(range(1, 10)), (n, h)
    print("all model solutions verified legal and complete (rows, cols, boxes)")
