#!/usr/bin/env python3
"""
Reference Sudoku solver and golden-file generator.

This is the correctness oracle for the whole project. It is deliberately NOT the
algorithm the hardware uses -- it solves with constraint propagation + MRV, so a
misunderstanding baked into the RTL cannot cancel itself out against the golden.

  generate goldens :  python solve_ref.py --gen
  check a run      :  python solve_ref.py --check easy1 <file-with-app-stdout>
  print a solution :  python solve_ref.py --solve hard1

Any command takes --variant <name> (default classic). The geometry lives in
bench/units.py and nowhere else, so the hackathon variant is a change to that file.
Non-classic goldens are written as <board>.<variant>.grid so they can never be
confused with the classic ones.

Board files are the course format: 81 two-digit hex bytes, whitespace-separated,
0 = empty. Goldens are written as one line of 81 digits.
"""
import sys, os, re, hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import units as UNITS               # the only place that knows the geometry

HERE    = os.path.dirname(os.path.abspath(__file__))
BOARDS  = os.path.join(HERE, "..", "sw", "apps", "sud_shared")
GOLDEN  = os.path.join(HERE, "golden")
NAMES   = ["easy1", "20blanks", "51blanks", "hard1"]


def read_board(name):
    p = os.path.join(BOARDS, "sudoku_input_%s.txt" % name)
    vals = [int(t, 16) for t in re.findall(r"[0-9A-Fa-f]{2}", open(p).read())]
    if len(vals) != 81:
        raise SystemExit("%s: expected 81 cells, got %d" % (name, len(vals)))
    return vals


def solve(cells, variant="classic"):
    """Constraint propagation + MRV. Returns the solved list, or None.

    Every rule comes from the units table, so a variant is a change to bench/units.py
    and nothing here. Nothing below may reintroduce row/column/box arithmetic."""
    us      = UNITS.units(variant)
    peers   = UNITS.peers(us)
    unit_of = UNITS.units_of(us)

    # candidate sets as 9-bit masks, bit d-1 set means d is possible
    ALL = 0x1FF
    cand = [ALL] * 81

    def assign(cand, i, d):
        """Place digit d at cell i, propagating. Returns new cand or None."""
        other = cand[i] & ~(1 << (d - 1))
        for b in range(9):
            if other >> b & 1:
                if not eliminate(cand, i, b + 1):
                    return None
        return cand

    def eliminate(cand, i, d):
        bit = 1 << (d - 1)
        if not cand[i] & bit:
            return True                      # already gone
        cand[i] &= ~bit
        if cand[i] == 0:
            return False                     # contradiction
        if cand[i] & (cand[i] - 1) == 0:     # exactly one candidate left
            v = cand[i].bit_length()
            for p in peers[i]:
                if not eliminate(cand, p, v):
                    return False
        # hidden singles: does d still fit anywhere in each unit of i?
        for u in unit_of[i]:
            spots = [j for j in u if cand[j] & bit]
            if not spots:
                return False
            if len(spots) == 1 and cand[spots[0]] != bit:
                if not assign(cand, spots[0], d):
                    return False
        return True

    for i, v in enumerate(cells):
        if v and not assign(cand, i, v):
            return None

    def search(cand):
        if all(c & (c - 1) == 0 for c in cand):
            return cand
        # MRV: fewest candidates among the undecided
        i = min((j for j in range(81) if bin(cand[j]).count("1") > 1),
                key=lambda j: bin(cand[j]).count("1"))
        for b in range(9):
            if cand[i] >> b & 1:
                trial = list(cand)
                if assign(trial, i, b + 1):
                    got = search(trial)
                    if got:
                        return got
        return None

    out = search(cand)
    if not out:
        return None
    sol = [c.bit_length() for c in out]

    # Never return an unvalidated grid. A propagation model in this project once placed
    # two naked singles for the same digit in the same unit, built an illegal board, and
    # returned it - because nothing checked. It then drove a whole roadmap. The oracle
    # must hold itself to the standard it holds the hardware to.
    bad = UNITS.illegal_units(sol, us, UNITS.labels(variant))
    if bad:
        raise SystemExit("oracle produced an ILLEGAL grid - duplicates in %s"
                         % ", ".join(bad[:4]))
    for i, v in enumerate(cells):
        if v and sol[i] != v:
            raise SystemExit("oracle changed a given: cell %d was %d, became %d"
                             % (i, v, sol[i]))
    return sol


def grid_str(vals):
    return "".join(str(v) for v in vals)


def golden_path(name, variant):
    tail = ".grid" if variant == "classic" else ".%s.grid" % variant
    return os.path.join(GOLDEN, name + tail)


def cmd_gen(variant="classic"):
    os.makedirs(GOLDEN, exist_ok=True)
    for n in NAMES:
        sol = solve(read_board(n), variant)
        if not sol:
            # Under a stricter variant a course board may simply have no solution.
            # That is information, not a crash: say so and carry on.
            print("%-10s NO SOLUTION under variant '%s'" % (n, variant)); continue
        s = grid_str(sol)
        open(golden_path(n, variant), "w", newline="\n").write(s + "\n")
        print("%-10s %s  md5=%s" % (n, s[:27] + "...", hashlib.md5(s.encode()).hexdigest()[:12]))


# The app's banner changed between reference versions:
#   older: "=== Solved ==="
#   newer: "=== Application reported Solved ==="   (ex3.1 checker update, Aug 2026)
# Match either, and anchor on the last one in the file so a board echoed earlier
# in the log can never be mistaken for the answer.
SOLVED_BANNER = re.compile(r"===\s*(?:Application reported\s+)?Solved\s*===")


def extract(text):
    """Pull the 81 solved digits out of app stdout."""
    hits = list(SOLVED_BANNER.finditer(text))
    if not hits:
        return None
    tail = text[hits[-1].end():]
    # Stop at the next banner/blank-line block so a later report cannot leak in.
    tail = tail.split("Solved board")[0]
    digits = re.findall(r"\d", tail)
    # Cells print with %d, so a corrupt nibble >= 10 emits TWO characters and shifts
    # everything after it. Demand exactly 81 rather than silently truncating.
    if len(digits) != 81:
        return None
    return "".join(digits)


def app_checker_verdict(text):
    """The app now runs its own checker. Report what it said, if anything."""
    m = re.search(r"Solved board (PASSED|FAILED) final checker", text)
    return m.group(1) if m else None


def cmd_check(name, path, variant="classic"):
    gp = golden_path(name, variant)
    if not os.path.exists(gp):
        print("FAIL %-10s no golden for variant '%s' - run --gen --variant %s"
              % (name, variant, variant)); return 1
    want = open(gp).read().strip()
    got = extract(open(path, errors="replace").read())
    if got is None:
        print("FAIL %-10s no solved grid found in %s" % (name, path)); return 1

    # Legality under the ACTIVE variant, checked before the golden comparison so the
    # message says *which rule* was broken rather than just "differs".
    bad = UNITS.illegal_units(got, UNITS.units(variant), UNITS.labels(variant))
    if bad:
        print("FAIL %-10s illegal under variant '%s' - duplicates in %s"
              % (name, variant, ", ".join(bad[:4]))); return 1

    if got != want:
        print("FAIL %-10s grid differs from golden" % name)
        print("  want %s" % want); print("  got  %s" % got); return 1
    verdict = app_checker_verdict(open(path, errors="replace").read())
    extra = "" if verdict is None else "  app-checker=%s" % verdict
    print("PASS %-10s md5=%s%s" % (name, hashlib.md5(got.encode()).hexdigest()[:12], extra))
    if verdict == "FAILED":
        print("  NOTE: our golden agrees but the app's own checker said FAILED - investigate")
        return 1
    return 0


if __name__ == "__main__":
    a = sys.argv[1:]
    variant = "classic"
    if "--variant" in a:
        k = a.index("--variant"); variant = a[k + 1]; del a[k:k + 2]
    if not a or a[0] == "--gen":
        cmd_gen(variant)
    elif a[0] == "--check":
        sys.exit(cmd_check(a[1], a[2], variant))
    elif a[0] == "--solve":
        sol = solve(read_board(a[1]), variant)
        print(grid_str(sol) if sol else "NO SOLUTION")
    else:
        print(__doc__)
