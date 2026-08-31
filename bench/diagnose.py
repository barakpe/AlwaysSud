#!/usr/bin/env python3
"""
When a board fails the correctness gate, say HOW it failed.

"Wrong answer" is not a diagnosis. The shape of the wrongness is, and in this design
the shapes are few and each points somewhere specific:

  - first wrong cell at a multiple of 32   -> the memory burst path, not the solver
  - wrong region is a shifted COPY         -> an index error, not a computation error
  - wrong cells are 0                      -> data never written back
  - a no-backtrack board fails             -> the search cannot be the cause
  - duplicates within a unit               -> the grid is illegal, not merely different

Usage:
  python diagnose.py <board> <captured-stdout>     diagnose a real run
  python diagnose.py --demo                        reproduce the known store bug
"""
import sys, os, re

HERE   = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden")
BURST  = 32                       # bytes per memory transaction in this design
NCELL  = 81

# boards that never backtrack - if one of these fails, the search is not involved
NO_BACKTRACK = {"20blanks"}


def units():
    u = []
    for r in range(9):
        u.append(("row %d" % r, [r * 9 + c for c in range(9)]))
    for c in range(9):
        u.append(("col %d" % c, [r * 9 + c for r in range(9)]))
    for b in range(9):
        br, bc = (b // 3) * 3, (b % 3) * 3
        u.append(("box %d" % b, [(br + k // 3) * 9 + bc + k % 3 for k in range(9)]))
    return u


def load_golden(name):
    return open(os.path.join(GOLDEN, name + ".grid")).read().strip()


def extract(text):
    m = list(re.finditer(r"===\s*(?:Application reported\s+)?Solved\s*===", text))
    if not m:
        return None
    tail = text[m[-1].end():].split("Solved board")[0]
    d = re.findall(r"\d", tail)
    return "".join(d) if len(d) == NCELL else None


def diagnose(name, got, want):
    print("board          : %s" % name)
    if got is None:
        print("VERDICT        : no 81-digit grid found in the output")
        print("                 -> the app did not print a solved board, or a cell")
        print("                    printed as two characters and shifted the parse")
        return
    if got == want:
        print("VERDICT        : matches golden")
        return

    bad = [i for i in range(NCELL) if got[i] != want[i]]
    first = bad[0]
    print("wrong cells    : %d of %d, first at %d" % (len(bad), NCELL, first))

    # 1. burst alignment
    if first % BURST == 0:
        print("burst align    : YES - first error at cell %d = burst %d boundary"
              % (first, first // BURST))
        print("                 -> points at the LOAD/STORE burst path, NOT the solver")
    else:
        print("burst align    : no - first error at %d, not a multiple of %d"
              % (first, BURST))

    # 2. zeros?
    zeros = [i for i in bad if got[i] == "0"]
    if zeros:
        print("zeros          : %d wrong cells are 0" % len(zeros))
        print("                 -> data was never written back; you are probably")
        print("                    looking at the ORIGINAL puzzle, blanks and all")

    # 3. is the wrong region a shifted copy of the right answer?
    for shift in range(1, NCELL):
        seg = [i for i in range(first, NCELL) if i - shift >= 0]
        if len(seg) >= 8 and all(got[i] == want[i - shift] for i in seg[:30]):
            print("shifted copy   : YES - got[%d:] equals want[%d:] (shift %d)"
                  % (first, first - shift, shift))
            print("                 -> an INDEX error, not a computation error.")
            print("                    Something addressed one place and fetched another.")
            if shift % BURST == 0:
                print("                    shift is %d burst(s) - a stale burst counter"
                      % (shift // BURST))
            break

    # 4. is the grid even legal?
    dups = []
    for label, cells in units():
        seen = [got[i] for i in cells if got[i] != "0"]
        if len(seen) != len(set(seen)):
            dups.append(label)
    if dups:
        print("legality       : ILLEGAL - duplicates in %d unit(s), e.g. %s"
              % (len(dups), ", ".join(dups[:4])))
        print("                 -> whatever produced this was not a solver result")
    else:
        print("legality       : the grid is a legal Sudoku, just not this puzzle's answer")

    # 5. did a board that cannot backtrack fail?
    if name in NO_BACKTRACK:
        print("search ruled out: %s never backtracks, and it still failed" % name)
        print("                 -> the search path cannot be the cause")


def show(s, label):
    print("\n%s" % label)
    for r in range(9):
        row = s[r * 9:(r + 1) * 9]
        print("   " + " ".join(row[0:3]) + " | " + " ".join(row[3:6]) + " | " + " ".join(row[6:9]))
        if r in (2, 5):
            print("   ------+-------+------")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--demo":
        want = load_golden("51blanks")
        # the pre-fix STORE: address advanced 0,32,64 but data was indexed 0,0,32
        got = want[0:32] + want[0:32] + want[32:49]
        show(want, "CORRECT")
        show(got, "WHAT THE BROKEN WRITE-BACK PRODUCED")
        print()
        diagnose("51blanks", got, want)
    elif len(a) == 2:
        want = load_golden(a[0])
        got = extract(open(a[1], errors="replace").read())
        diagnose(a[0], got, want)
    else:
        print(__doc__)
